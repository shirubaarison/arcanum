defmodule ArcanumWeb.CommunityLive.Show do
  use ArcanumWeb, :live_view

  alias Arcanum.Communities
  alias Arcanum.Rooms
  alias Arcanum.Rooms.Room
  alias ArcanumWeb.FailureLog
  alias ArcanumWeb.RoomComponents

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :subscribed_community_id, nil)}

  @impl true
  def handle_params(%{"name" => name}, _uri, socket) do
    scope = socket.assigns.current_scope

    with {:ok, community} <- Communities.get_community_by_name(scope, name),
         %Ecto.Changeset{} = changeset <- Communities.change_post(scope, community),
         posts when is_list(posts) <- Communities.list_posts(scope, community) do
      {:noreply,
       socket
       |> subscribe(community)
       |> assign(
         community: community,
         page_title: community.name,
         form: to_form(changeset)
       )
       |> stream(:posts, posts, reset: true)
       |> load_rooms(true)}
    else
      {:error, reason} -> {:noreply, unavailable(socket, reason)}
    end
  end

  defp load_rooms(socket, reset_form \\ false) do
    scope = socket.assigns.current_scope
    community = socket.assigns.community

    case Rooms.list_rooms_with_participants(scope, community) do
      rooms when is_list(rooms) ->
        changeset = Rooms.change_room(scope, %Room{community_id: community.id})
        can_create_room = match?(%Ecto.Changeset{}, changeset)

        room_form = room_form(changeset, socket.assigns[:room_form], reset_form)

        socket =
          socket
          |> assign(:can_create_room, can_create_room)
          |> assign(:room_form, room_form)
          |> stream(:rooms, rooms, reset: true)

        if socket.assigns.live_action == :new_room and not can_create_room do
          room_denied(socket)
        else
          socket
        end

      {:error, reason} ->
        unavailable(socket, reason)
    end
  end

  defp room_form(%Ecto.Changeset{} = changeset, existing, reset?) do
    if reset?, do: to_form(changeset), else: existing || to_form(changeset)
  end

  defp room_form(_changeset, _existing, _reset?), do: nil

  defp room_denied(socket) do
    socket
    |> put_flash(:error, "Only community owners and admins can create rooms.")
    |> push_patch(to: ~p"/communities/#{socket.assigns.community}")
  end

  defp unavailable(socket, reason) do
    FailureLog.log("community lookup", reason)

    if socket.assigns.subscribed_community_id do
      Communities.unsubscribe_community(
        socket.assigns.current_scope,
        %Arcanum.Communities.Community{id: socket.assigns.subscribed_community_id}
      )

      Rooms.unsubscribe_rooms(socket.assigns.current_scope, %Arcanum.Communities.Community{
        id: socket.assigns.subscribed_community_id
      })
    end

    socket
    |> put_flash(:error, "Community not found or you don't have access.")
    |> push_navigate(to: ~p"/communities")
  end

  defp subscribe(socket, community) do
    if connected?(socket) and socket.assigns.subscribed_community_id != community.id do
      if socket.assigns.subscribed_community_id do
        Communities.unsubscribe_community(
          socket.assigns.current_scope,
          %Arcanum.Communities.Community{id: socket.assigns.subscribed_community_id}
        )

        Rooms.unsubscribe_rooms(socket.assigns.current_scope, %Arcanum.Communities.Community{
          id: socket.assigns.subscribed_community_id
        })
      end

      result =
        with :ok <- Communities.subscribe_community(socket.assigns.current_scope, community),
             do: Rooms.subscribe_rooms(socket.assigns.current_scope, community)

      case result do
        :ok -> assign(socket, :subscribed_community_id, community.id)
        {:error, reason} -> unavailable(socket, reason)
      end
    else
      socket
    end
  end

  @impl true
  def handle_info({:community_changed, id}, %{assigns: %{community: %{id: id}}} = socket) do
    scope = socket.assigns.current_scope

    with {:ok, community} <- Communities.get_community(scope, id),
         posts when is_list(posts) <- Communities.list_posts(scope, community) do
      {:noreply,
       socket
       |> assign(community: community, page_title: community.name)
       |> stream(:posts, posts, reset: true)
       |> load_rooms()}
    else
      {:error, reason} -> {:noreply, unavailable(socket, reason)}
    end
  end

  def handle_info({:community_changed, _id}, socket), do: {:noreply, socket}

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, load_rooms(socket)}
  end

  def handle_info({:room_changed, _id}, socket), do: {:noreply, load_rooms(socket)}
  def handle_info({:room_message_changed, _id}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate_room", %{"room" => attrs}, socket) do
    case Rooms.change_room(
           socket.assigns.current_scope,
           %Room{community_id: socket.assigns.community.id},
           attrs
         ) do
      %Ecto.Changeset{} = changeset ->
        {:noreply, assign(socket, :room_form, to_form(Map.put(changeset, :action, :validate)))}

      {:error, _reason} ->
        {:noreply, room_denied(socket)}
    end
  end

  def handle_event("save_room", %{"room" => attrs}, socket) do
    case Rooms.create_room(socket.assigns.current_scope, socket.assigns.community, attrs) do
      {:ok, _room} ->
        {:noreply,
         socket
         |> put_flash(:info, "Room created.")
         |> push_patch(to: ~p"/communities/#{socket.assigns.community}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :room_form, to_form(changeset))}

      {:error, _reason} ->
        {:noreply, room_denied(socket)}
    end
  end

  def handle_event("validate", %{"post" => attrs}, socket) do
    changeset =
      Communities.change_post(socket.assigns.current_scope, socket.assigns.community, attrs)

    case changeset do
      %Ecto.Changeset{} ->
        {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :validate)))}

      {:error, reason} ->
        {:noreply, unavailable(socket, reason)}
    end
  end

  def handle_event("save", %{"post" => attrs}, socket) do
    case Communities.create_post(socket.assigns.current_scope, socket.assigns.community, attrs) do
      {:ok, post} ->
        {:noreply,
         push_navigate(socket, to: ~p"/communities/#{socket.assigns.community}/posts/#{post}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        FailureLog.log("create post", changeset)
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, reason} ->
        FailureLog.log("create post", reason)
        {:noreply, put_flash(socket, :error, "You no longer have access to this community.")}
    end
  end

  def handle_event("vote", %{"id" => id, "vote" => value}, socket) do
    scope = socket.assigns.current_scope
    community = socket.assigns.community

    with {:ok, post} <- Communities.get_post(scope, community, id),
         {:ok, _} <- Communities.vote_post(scope, post, vote_value(value)),
         {:ok, post} <- Communities.get_post(scope, community, id) do
      {:noreply, stream_insert(socket, :posts, post)}
    else
      {:error, reason} ->
        FailureLog.log("vote post", reason)
        {:noreply, put_flash(socket, :error, "Could not save your vote.")}
    end
  end

  defp vote_value("1"), do: 1
  defp vote_value("-1"), do: -1
  defp vote_value("0"), do: 0
  defp vote_value(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} community>
      <.link navigate={~p"/communities"} class="text-xs text-stone-500 hover:underline">← communities</.link>
      <div class="mt-3 flex flex-wrap items-center gap-4">
        <h1 id="community-name" class="text-xl font-bold">{@community.name}</h1>
        <.link
          id="community-settings"
          navigate={~p"/communities/#{@community}/edit"}
          class="text-xs text-stone-500 hover:underline"
        >settings & members</.link>
      </div>
      <p class="mt-2 whitespace-pre-wrap break-words text-stone-600">{@community.description}</p>
      <div class="grid items-start gap-8 lg:grid-cols-[minmax(0,1fr)_16rem]">
        <section id="community-content">
          <%= if @live_action == :new_room and @can_create_room do %>
            <div class="rounded-lg border border-stone-200 bg-white p-5 sm:p-6">
              <h2 id="new-room-title" class="text-lg font-semibold">Create a room</h2>
              <p class="mt-1 text-sm text-stone-500">
                Give your community a space to talk. Every member can join the conversation.
              </p>
              <.form
                for={@room_form}
                id="room-form"
                phx-change="validate_room"
                phx-submit="save_room"
                class="mt-5 space-y-4"
              >
                <.input
                  field={@room_form[:name]}
                  label="Room name"
                  placeholder="e.g. General"
                  required
                  maxlength="255"
                  class="community-input"
                />
                <div class="flex items-center gap-4">
                  <button id="submit-room" class="community-button" phx-disable-with="Creating...">Create room</button>
                  <.link
                    id="cancel-room"
                    patch={~p"/communities/#{@community}"}
                    class="text-stone-500 transition-colors hover:text-stone-800"
                  >Cancel</.link>
                </div>
              </.form>
            </div>
          <% else %>
            <%= if @live_action == :new_post do %>
              <h2 class="font-bold">Write a post</h2>
              <.form
                for={@form}
                id="post-form"
                phx-change="validate"
                phx-submit="save"
                class="max-w-2xl space-y-4"
              >
                <.input
                  field={@form[:title]}
                  label="Title"
                  required
                  maxlength="255"
                  class="community-input"
                />
                <.input
                  field={@form[:body]}
                  type="textarea"
                  label="Text"
                  required
                  rows="8"
                  class="community-input"
                />
                <button id="submit-post" class="community-button" phx-disable-with="Posting...">Post</button>
                <.link
                  navigate={~p"/communities/#{@community}"}
                  class="ml-3 text-stone-500 hover:underline"
                >cancel</.link>
              </.form>
            <% else %>
              <.link
                id="new-post"
                navigate={~p"/communities/#{@community}/posts/new"}
                class="community-button mt-2 inline-block"
              >write a post</.link>
              <div id="posts" phx-update="stream" class="mt-6 space-y-5">
                <p id="posts-empty" class="hidden text-stone-500 only:block">
                  No posts yet. Start a conversation.
                </p>
                <article :for={{id, post} <- @streams.posts} id={id} class="flex items-start gap-3">
                  <div class="flex flex-col items-center text-xs">
                    <button
                      id={"upvote-post-#{post.id}"}
                      phx-click="vote"
                      phx-value-id={post.id}
                      phx-value-vote={if(post.my_vote == 1, do: 0, else: 1)}
                      aria-label="Upvote post"
                      aria-pressed={to_string(post.my_vote == 1)}
                      class={[
                        "cursor-pointer hover:text-blue-600",
                        post.my_vote == 1 && "text-blue-600"
                      ]}
                    ><.icon name="hero-chevron-up" class="size-4" /></button>
                    <span id={"post-score-#{post.id}"}>{post.score}</span>
                    <button
                      id={"downvote-post-#{post.id}"}
                      phx-click="vote"
                      phx-value-id={post.id}
                      phx-value-vote={if(post.my_vote == -1, do: 0, else: -1)}
                      aria-label="Downvote post"
                      aria-pressed={to_string(post.my_vote == -1)}
                      class={[
                        "cursor-pointer hover:text-blue-600",
                        post.my_vote == -1 && "text-blue-600"
                      ]}
                    ><.icon name="hero-chevron-down" class="size-4" /></button>
                  </div>
                  <div class="min-w-0">
                    <.link
                      id={"post-link-#{post.id}"}
                      navigate={~p"/communities/#{@community}/posts/#{post}"}
                      class="break-words font-medium hover:underline"
                    >{post.title}</.link>
                    <p class="mt-1 break-all text-xs text-stone-500">
                      by
                      <.link
                        id={"post-author-#{post.id}"}
                        navigate={~p"/#{post.author.username}"}
                        class="hover:underline"
                      >{post.author.username}</.link>
                      · <.local_time id={"post-time-#{post.id}"} value={post.inserted_at} /> ·
                      <.link
                        navigate={~p"/communities/#{@community}/posts/#{post}"}
                        class="hover:underline"
                      >comments</.link>
                    </p>
                  </div>
                </article>
              </div>
            <% end %>
          <% end %>
        </section>
        <RoomComponents.sidebar
          rooms={@streams.rooms}
          community={@community}
          can_create_room={@can_create_room}
          patch_create
        />
      </div>
    </Layouts.app>
    """
  end
end
