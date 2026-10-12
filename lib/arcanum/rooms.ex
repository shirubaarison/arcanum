defmodule Arcanum.Rooms do
  @moduledoc """
  Community-scoped rooms and messages.

  All community members can read rooms and send messages. Owners and admins
  manage rooms; message authors can edit and delete their own messages.
  Inaccessible reads return `{:error, :not_found}` and mutations return
  `{:error, :unauthorized}`. Deleted communities are inaccessible.
  """

  import Ecto.Query

  alias Arcanum.Accounts.{Scope, User}
  alias Arcanum.Communities
  alias Arcanum.Communities.{Community, CommunityMembership}
  alias Arcanum.Repo
  alias Arcanum.Rooms.{Message, Room}
  alias Arcanum.Rooms.Presence

  @doc "Subscribes to ID-only room events and presence for an accessible community."
  def subscribe_rooms(scope, %Community{id: id}) do
    with {:ok, _} <- Communities.get_community(scope, id) do
      Phoenix.PubSub.subscribe(Arcanum.PubSub, rooms_topic(id))
    end
  end

  def unsubscribe_rooms(%Scope{}, %Community{id: id}) do
    Phoenix.PubSub.unsubscribe(Arcanum.PubSub, rooms_topic(id))
  end

  def track_room(scope, %Room{id: id}) do
    with {:ok, room} <- get_room(scope, id) do
      Presence.track(self(), rooms_topic(room.community_id), to_string(scope.user.id), %{
        room_id: room.id
      })
    end
  end

  def untrack_room(%Scope{user: %User{id: user_id}}, %Room{community_id: community_id}) do
    Presence.untrack(self(), rooms_topic(community_id), to_string(user_id))
  end

  @doc "Lists rooms with current viewers, deduplicated across browser tabs."
  def list_rooms_with_participants(scope, %Community{id: id} = community) do
    with rooms when is_list(rooms) <- list_rooms(scope, community) do
      presence = Presence.list(rooms_topic(id))

      members =
        Repo.all(
          from m in CommunityMembership,
            join: u in User,
            on: u.id == m.user_id,
            where: m.community_id == ^id,
            select: %{id: u.id, username: u.username}
        )

      Enum.map(rooms, fn room ->
        participants =
          members
          |> Enum.filter(&viewing_room?(presence, &1.id, room.id))
          |> Enum.sort_by(& &1.username)

        room |> Map.from_struct() |> Map.put(:participants, participants)
      end)
    end
  end

  defp viewing_room?(presence, user_id, room_id) do
    case Map.get(presence, to_string(user_id)) do
      %{metas: metas} -> Enum.any?(metas, &(&1.room_id == room_id))
      nil -> false
    end
  end

  defp rooms_topic(id), do: "community_rooms:#{id}"

  defp notify({:ok, record} = result, community_id, event) do
    Phoenix.PubSub.broadcast(Arcanum.PubSub, rooms_topic(community_id), {event, record.id})
    result
  end

  defp notify(result, _community_id, _event), do: result

  def list_rooms(scope, %Community{id: id}) do
    with {:ok, _community} <- Communities.get_community(scope, id) do
      scope
      |> accessible_rooms()
      |> where([r], r.community_id == ^id)
      |> order_by([r], asc: r.name, asc: r.id)
      |> Repo.all()
    end
  end

  def get_room(scope, id), do: fetch(scope |> accessible_rooms(), id)

  def create_room(scope, %Community{id: id}, attrs) do
    with :ok <- authorize_room_management(scope, id) do
      %Room{community_id: id}
      |> Room.changeset(attrs)
      |> Repo.insert()
      |> notify(id, :room_changed)
    end
  end

  def update_room(scope, %Room{id: id}, attrs) do
    with {:ok, room} <- mutation_record(get_room(scope, id)),
         :ok <- authorize_room_management(scope, room.community_id) do
      room |> Room.changeset(attrs) |> Repo.update() |> notify(room.community_id, :room_changed)
    end
  end

  def delete_room(scope, %Room{id: id}) do
    with {:ok, room} <- mutation_record(get_room(scope, id)),
         :ok <- authorize_room_management(scope, room.community_id) do
      room |> Repo.delete() |> notify(room.community_id, :room_changed)
    end
  end

  def change_room(scope, room, attrs \\ %{})

  def change_room(scope, %Room{id: nil, community_id: community_id} = room, attrs) do
    with :ok <- authorize_room_management(scope, community_id) do
      Room.changeset(room, attrs)
    end
  end

  def change_room(scope, %Room{id: id}, attrs) do
    with {:ok, room} <- get_room(scope, id),
         :ok <- authorize_room_management(scope, room.community_id) do
      Room.changeset(room, attrs)
    end
  end

  @doc "Returns the latest 100 messages in chronological order, with users preloaded."
  def list_messages(scope, %Room{id: id}) do
    with {:ok, _room} <- get_room(scope, id) do
      scope
      |> accessible_messages()
      |> where([m], m.room_id == ^id)
      |> order_by([m], desc: m.inserted_at, desc: m.id)
      |> limit(100)
      |> preload(:user)
      |> Repo.all()
      |> Enum.reverse()
    end
  end

  def get_message(scope, id), do: fetch(scope |> accessible_messages() |> preload(:user), id)

  def create_message(%Scope{user: %User{id: user_id}} = scope, %Room{id: id}, attrs) do
    with {:ok, room} <- mutation_record(get_room(scope, id)) do
      %Message{room_id: room.id, user_id: user_id}
      |> Message.changeset(attrs)
      |> Repo.insert()
      |> notify(room.community_id, :room_message_changed)
    end
  end

  def update_message(scope, %Message{id: id}, attrs) do
    with {:ok, message} <- mutation_record(get_message(scope, id)),
         :ok <- authorize_author(scope, message) do
      message |> Message.changeset(attrs) |> Repo.update()
    end
  end

  def delete_message(scope, %Message{id: id}) do
    with {:ok, message} <- mutation_record(get_message(scope, id)),
         :ok <- authorize_author(scope, message) do
      Repo.delete(message)
    end
  end

  def change_message(scope, message, attrs \\ %{})

  def change_message(scope, %Message{id: nil, room_id: room_id}, attrs) do
    with {:ok, room} <- get_room(scope, room_id) do
      Message.changeset(%Message{room_id: room.id, user_id: scope.user.id}, attrs)
    end
  end

  def change_message(scope, %Message{id: id}, attrs) do
    with {:ok, message} <- get_message(scope, id),
         :ok <- authorize_author(scope, message) do
      Message.changeset(message, attrs)
    end
  end

  defp accessible_rooms(%Scope{user: %User{id: user_id}}) do
    from r in Room,
      join: c in Community,
      on: c.id == r.community_id,
      join: m in CommunityMembership,
      on: m.community_id == c.id,
      where: m.user_id == ^user_id and is_nil(c.deleted_at)
  end

  defp accessible_messages(scope) do
    from m in Message, join: r in subquery(accessible_rooms(scope)), on: r.id == m.room_id
  end

  defp authorize_room_management(scope, community_id) do
    with {:ok, _community} <- Communities.get_community(scope, community_id),
         %CommunityMembership{role: role} when role in [:owner, :admin] <-
           Repo.get_by(CommunityMembership, community_id: community_id, user_id: scope.user.id) do
      :ok
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp authorize_author(%Scope{user: %User{id: id}}, %Message{user_id: id}), do: :ok
  defp authorize_author(_scope, _message), do: {:error, :unauthorized}

  defp fetch(query, id) do
    with {:ok, id} when is_integer(id) and id > 0 <- Ecto.Type.cast(:id, id),
         record when not is_nil(record) <- Repo.get(query, id) do
      {:ok, record}
    else
      _ -> {:error, :not_found}
    end
  end

  defp mutation_record({:error, :not_found}), do: {:error, :unauthorized}
  defp mutation_record(result), do: result
end
