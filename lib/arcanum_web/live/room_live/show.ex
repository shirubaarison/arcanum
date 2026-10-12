defmodule ArcanumWeb.RoomLive.Show do
  use ArcanumWeb, :live_view

  alias Arcanum.{Communities, Rooms}
  alias Arcanum.Rooms.{Message, Room}
  alias ArcanumWeb.RoomComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :tracked_room, nil)}
  end

  @impl true
  def handle_params(%{"community_name" => name, "id" => id}, _uri, socket) do
    scope = socket.assigns.current_scope

    with {:ok, community} <- Communities.get_community_by_name(scope, name),
         {:ok, room} <- Rooms.get_room(scope, id),
         true <- room.community_id == community.id,
         %Ecto.Changeset{} = changeset <- Rooms.change_message(scope, %Message{room_id: room.id}) do
      socket =
        socket
        |> assign(
          community: community,
          room: room,
          page_title: "#{room.name} · #{community.name}",
          form: to_form(changeset)
        )
        |> subscribe_and_track()
        |> refresh_rooms()
        |> refresh_messages()

      {:noreply, socket}
    else
      _ -> {:noreply, unavailable(socket)}
    end
  end

  defp subscribe_and_track(socket) do
    if connected?(socket) and socket.assigns.tracked_room != socket.assigns.room do
      scope = socket.assigns.current_scope
      socket = leave_room(socket)

      with :ok <- Communities.subscribe_community(scope, socket.assigns.community),
           :ok <- Rooms.subscribe_rooms(scope, socket.assigns.community),
           {:ok, _} <- Rooms.track_room(scope, socket.assigns.room) do
        assign(socket, :tracked_room, socket.assigns.room)
      else
        _ -> unavailable(socket)
      end
    else
      socket
    end
  end

  defp leave_room(%{assigns: %{tracked_room: nil}} = socket), do: socket

  defp leave_room(socket) do
    scope = socket.assigns.current_scope
    room = socket.assigns.tracked_room
    community = %Arcanum.Communities.Community{id: room.community_id}
    Rooms.untrack_room(scope, room)
    Rooms.unsubscribe_rooms(scope, community)
    Communities.unsubscribe_community(scope, community)
    assign(socket, :tracked_room, nil)
  end

  defp refresh_rooms(socket) do
    scope = socket.assigns.current_scope

    case Rooms.list_rooms_with_participants(scope, socket.assigns.community) do
      rooms when is_list(rooms) ->
        can_create =
          match?(
            %Ecto.Changeset{},
            Rooms.change_room(scope, %Room{community_id: socket.assigns.community.id})
          )

        socket |> assign(:can_create_room, can_create) |> stream(:rooms, rooms, reset: true)

      _ ->
        unavailable(socket)
    end
  end

  defp refresh_messages(socket) do
    case Rooms.list_messages(socket.assigns.current_scope, socket.assigns.room) do
      messages when is_list(messages) -> stream(socket, :messages, messages, reset: true)
      _ -> unavailable(socket)
    end
  end

  defp unavailable(socket) do
    socket
    |> leave_room()
    |> put_flash(:error, "Room not found or you don't have access.")
    |> push_navigate(to: ~p"/communities")
  end

  @impl true
  def handle_event("validate", %{"message" => attrs}, socket) do
    case Rooms.change_message(
           socket.assigns.current_scope,
           %Message{room_id: socket.assigns.room.id},
           attrs
         ) do
      %Ecto.Changeset{} = changeset ->
        {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :validate)))}

      _ ->
        {:noreply, unavailable(socket)}
    end
  end

  def handle_event("send", %{"message" => attrs}, socket) do
    scope = socket.assigns.current_scope
    room = socket.assigns.room

    case Rooms.create_message(scope, room, attrs) do
      {:ok, _message} ->
        changeset = Rooms.change_message(scope, %Message{room_id: room.id})

        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> refresh_messages()
         |> push_event("chat:sent", %{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      _ ->
        {:noreply, unavailable(socket)}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, refresh_rooms(socket)}
  end

  def handle_info({:room_message_changed, _id}, socket), do: {:noreply, refresh_messages(socket)}

  def handle_info({event, _id}, socket) when event in [:community_changed, :room_changed] do
    scope = socket.assigns.current_scope

    with {:ok, community} <- Communities.get_community(scope, socket.assigns.community.id),
         {:ok, room} <- Rooms.get_room(scope, socket.assigns.room.id) do
      {:noreply, socket |> assign(community: community, room: room) |> refresh_rooms()}
    else
      _ -> {:noreply, unavailable(socket)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} community>
      <.link id="back-community" navigate={~p"/communities/#{@community}"} class="text-xs text-stone-500 hover:underline">← {@community.name}</.link>
      <div id="chatroom" class="mt-4 grid items-start gap-4 md:grid-cols-[13rem_minmax(0,1fr)]">
        <RoomComponents.sidebar
          rooms={@streams.rooms}
          community={@community}
          current_room_id={@room.id}
          can_create_room={@can_create_room}
        />
        <section
          aria-labelledby="room-name"
          class="flex h-[70dvh] min-h-96 min-w-0 flex-col border border-stone-200 bg-white"
        >
          <header class="border-b border-stone-200 px-4 py-3">
            <h1 id="room-name" class="font-semibold">
              <span class="mr-2 text-stone-400">#</span>{@room.name}
            </h1>
          </header>
          <div
            id="chat-scroll"
            phx-hook="ChatScroll"
            class="min-h-0 flex-1 overflow-y-auto overscroll-contain"
            tabindex="0"
            aria-label="Chat history"
          >
            <div
              id="messages"
              phx-update="stream"
              role="log"
              aria-live="polite"
              aria-relevant="additions"
              class="space-y-1 px-4 py-4"
            >
              <p id="messages-empty" class="hidden py-8 text-sm text-stone-500 only:block">
                No messages yet. Say hello.
              </p>
              <article :for={{id, message} <- @streams.messages} id={id} class="py-2">
                <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                  <.link
                    id={"message-user-#{message.id}"}
                    navigate={~p"/#{message.user.username}"}
                    class="break-all text-sm font-semibold hover:underline"
                  >{message.user.username}</.link>
                  <span class="text-xs text-stone-400"><.local_time
                    id={"message-time-#{message.id}"}
                    value={message.inserted_at}
                  /></span>
                </div>
                <p
                  id={"message-body-#{message.id}"}
                  class="m-1 break-words text-sm"
                >
                  {message.message}
                </p>
              </article>
            </div>
          </div>
          <.form
            for={@form}
            id="message-form"
            phx-change="validate"
            phx-submit="send"
            class="border-t border-stone-200 p-3"
          >
            <div class="flex items-center gap-2">
              <div class="min-w-0 flex-1">
                <.input
                  field={@form[:message]}
                  type="textarea"
                  aria-label="Message"
                  placeholder={"Message ##{@room.name}"}
                  rows="2"
                  required
                  maxlength="50000"
                  class="community-input"
                />
              </div>
              <button
                id="send-message"
                type="submit"
                aria-label="Send message"
                title="Send message"
                class="flex size-10 shrink-0 cursor-pointer items-center justify-center rounded text-blue-600 transition-colors hover:bg-blue-50 hover:text-blue-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600 disabled:cursor-wait disabled:opacity-50"
              >
                <.icon name="hero-paper-airplane" class="size-5 phx-submit-loading:animate-pulse" />
              </button>
            </div>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
