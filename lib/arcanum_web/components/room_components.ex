defmodule ArcanumWeb.RoomComponents do
  @moduledoc "Shared room navigation and current viewers."
  use ArcanumWeb, :html

  attr :rooms, :any, required: true
  attr :community, :any, required: true
  attr :current_room_id, :integer, default: nil
  attr :can_create_room, :boolean, default: false
  attr :patch_create, :boolean, default: false

  def sidebar(assigns) do
    ~H"""
    <aside
      id="rooms-sidebar"
      aria-labelledby="rooms-heading"
      class="min-w-0 border border-stone-200 bg-white p-4"
    >
      <h2 id="rooms-heading" class="text-xs font-semibold uppercase tracking-wide text-stone-500">
        Rooms
      </h2>
      <div id="rooms" phx-update="stream" class="mt-3 space-y-1">
        <p id="rooms-empty" class="hidden py-2 text-xs text-stone-500 only:block">No rooms yet.</p>
        <div :for={{id, room} <- @rooms} id={id}>
          <.link
            id={"room-link-#{room.id}"}
            navigate={~p"/communities/#{@community}/rooms/#{room.id}"}
            aria-current={if(@current_room_id == room.id, do: "page", else: nil)}
            class={[
              "flex items-start gap-2 px-2 py-2 transition-colors hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-blue-600",
              @current_room_id == room.id && "bg-blue-50 text-blue-700"
            ]}
          >
            <span aria-hidden="true" class="text-stone-400">#</span>
            <span class="min-w-0 break-words">{room.name}</span>
          </.link>
          <ul
            :if={room.participants != []}
            id={"room-users-#{room.id}"}
            aria-label={"Members in #{room.name}"}
            class="ml-7 space-y-1 pb-2 text-xs text-stone-500"
          >
            <li :for={user <- room.participants} id={"room-user-#{room.id}-#{user.id}"}>
              <.link
                navigate={~p"/#{user.username}"}
                class="break-all hover:text-blue-600 hover:underline"
              >{user.username}</.link>
            </li>
          </ul>
        </div>
      </div>
      <.link
        :if={@can_create_room}
        id="new-room"
        patch={if(@patch_create, do: ~p"/communities/#{@community}/rooms/new")}
        navigate={if(not @patch_create, do: ~p"/communities/#{@community}/rooms/new")}
        class="mt-4 flex items-center gap-1 border-t border-stone-100 pt-3 text-xs text-blue-600 hover:underline"
      >
        <.icon name="hero-plus" class="size-3" /> Create room
      </.link>
    </aside>
    """
  end
end
