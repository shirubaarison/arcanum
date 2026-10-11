defmodule ArcanumWeb.CommunityLive.Show do
  use ArcanumWeb, :live_view

  alias Arcanum.Communities

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :subscribed_community_id, nil)}

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    scope = socket.assigns.current_scope
    community = Communities.get_community!(scope, id)

    {:noreply,
     socket
     |> subscribe(community)
     |> assign(
       community: community,
       page_title: community.name,
       form: to_form(Communities.change_post(scope, community))
     )
     |> stream(:posts, Communities.list_posts(scope, community), reset: true)}
  rescue
    _ in [Ecto.NoResultsError, Ecto.Query.CastError] ->
      {:noreply,
       socket
       |> put_flash(:error, "Community not found or you don't have access.")
       |> push_navigate(to: ~p"/communities")}
  end

  defp subscribe(socket, community) do
    if connected?(socket) and socket.assigns.subscribed_community_id != community.id do
      if socket.assigns.subscribed_community_id do
        Communities.unsubscribe_community(
          socket.assigns.current_scope,
          %Arcanum.Communities.Community{id: socket.assigns.subscribed_community_id}
        )
      end

      Communities.subscribe_community(socket.assigns.current_scope, community)
      assign(socket, :subscribed_community_id, community.id)
    else
      socket
    end
  end

  @impl true
  def handle_info({:community_changed, id}, %{assigns: %{community: %{id: id}}} = socket) do
    scope = socket.assigns.current_scope
    community = Communities.get_community!(scope, id)

    {:noreply,
     socket
     |> assign(community: community, page_title: community.name)
     |> stream(:posts, Communities.list_posts(scope, community), reset: true)}
  rescue
    Ecto.NoResultsError ->
      Communities.unsubscribe_community(socket.assigns.current_scope, socket.assigns.community)

      {:noreply,
       socket
       |> put_flash(:error, "Community not found or you don't have access.")
       |> push_navigate(to: ~p"/communities")}
  end

  def handle_info({:community_changed, _id}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", %{"post" => attrs}, socket) do
    changeset =
      Communities.change_post(socket.assigns.current_scope, socket.assigns.community, attrs)

    {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :validate)))}
  end

  def handle_event("save", %{"post" => attrs}, socket) do
    case Communities.create_post(socket.assigns.current_scope, socket.assigns.community, attrs) do
      {:ok, post} ->
        {:noreply,
         push_navigate(socket, to: ~p"/communities/#{socket.assigns.community}/posts/#{post}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You no longer have access to this community.")}
    end
  end

  def handle_event("vote", %{"id" => id, "vote" => value}, socket) do
    scope = socket.assigns.current_scope
    community = socket.assigns.community
    post = Communities.get_post!(scope, community, id)

    case Communities.vote_post(scope, post, vote_value(value)) do
      {:ok, _} ->
        {:noreply, stream_insert(socket, :posts, Communities.get_post!(scope, community, id))}

      {:error, _} ->
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

      <%= if @live_action == :new_post do %>
        <h2 class="mb-4 mt-6 font-bold">Write a post</h2>
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
          <.link navigate={~p"/communities/#{@community}"} class="ml-3 text-stone-500 hover:underline">cancel</.link>
        </.form>
      <% else %>
        <.link
          id="new-post"
          navigate={~p"/communities/#{@community}/posts/new"}
          class="community-button mt-5 inline-block"
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
                class={["cursor-pointer hover:text-blue-600", post.my_vote == 1 && "text-blue-600"]}
              ><.icon name="hero-chevron-up" class="size-4" /></button>
              <span id={"post-score-#{post.id}"}>{post.score}</span>
              <button
                id={"downvote-post-#{post.id}"}
                phx-click="vote"
                phx-value-id={post.id}
                phx-value-vote={if(post.my_vote == -1, do: 0, else: -1)}
                aria-label="Downvote post"
                aria-pressed={to_string(post.my_vote == -1)}
                class={["cursor-pointer hover:text-blue-600", post.my_vote == -1 && "text-blue-600"]}
              ><.icon name="hero-chevron-down" class="size-4" /></button>
            </div>
            <div class="min-w-0">
              <.link
                id={"post-link-#{post.id}"}
                navigate={~p"/communities/#{@community}/posts/#{post}"}
                class="break-words font-medium hover:underline"
              >{post.title}</.link>
              <p class="mt-1 break-all text-xs text-stone-500">
                by {post.author.username} · {Calendar.strftime(post.inserted_at, "%b %d, %Y")} ·
                <.link navigate={~p"/communities/#{@community}/posts/#{post}"} class="hover:underline">comments</.link>
              </p>
            </div>
          </article>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
