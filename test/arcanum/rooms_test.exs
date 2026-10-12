defmodule Arcanum.RoomsTest do
  use Arcanum.DataCase, async: true

  import Arcanum.AccountsFixtures

  alias Arcanum.Accounts.Scope
  alias Arcanum.{Communities, Rooms}
  alias Arcanum.Rooms.{Message, Room}

  setup do
    owner = Scope.for_user(unconfirmed_user_fixture())
    member = Scope.for_user(unconfirmed_user_fixture())
    outsider = Scope.for_user(unconfirmed_user_fixture())
    {:ok, community} = Communities.create_community(owner, %{name: "Chat"})
    {:ok, membership} = Communities.add_member(owner, community, member.user)
    {:ok, room} = Rooms.create_room(owner, community, %{name: "General"})

    %{
      owner: owner,
      member: member,
      outsider: outsider,
      community: community,
      membership: membership,
      room: room
    }
  end

  test "room CRUD is restricted to owners and admins", c do
    assert Rooms.list_rooms(c.member, c.community) == [c.room]
    assert {:ok, _} = Rooms.get_room(c.member, c.room.id)
    assert {:error, :unauthorized} = Rooms.create_room(c.member, c.community, %{name: "X"})
    assert {:error, :unauthorized} = Rooms.update_room(c.member, c.room, %{name: "X"})
    assert {:error, :unauthorized} = Rooms.delete_room(c.member, c.room)
    assert Rooms.change_room(c.owner, c.room).valid?
    assert {:ok, room} = Rooms.update_room(c.owner, c.room, %{name: " Updated "})
    assert room.name == "Updated"
    assert {:ok, _} = Communities.update_membership(c.owner, c.membership, %{role: :admin})
    assert {:ok, _} = Rooms.create_room(c.member, c.community, %{name: "Admin room"})
    assert {:ok, _} = Rooms.delete_room(c.member, room)
  end

  test "messages are shared, but only their authors can mutate them", c do
    assert {:ok, message} =
             Rooms.create_message(c.member, c.room, %{
               message: "Hello",
               user_id: c.owner.user.id,
               room_id: -1
             })

    assert message.user_id == c.member.user.id
    assert message.room_id == c.room.id
    assert [loaded] = Rooms.list_messages(c.owner, c.room)
    assert loaded.user.id == c.member.user.id
    assert {:ok, _} = Rooms.get_message(c.owner, message.id)
    assert {:error, :unauthorized} = Rooms.update_message(c.owner, message, %{message: "X"})
    assert {:error, :unauthorized} = Rooms.delete_message(c.owner, message)
    assert Rooms.change_message(c.member, message).valid?
    assert {:ok, updated} = Rooms.update_message(c.member, message, %{message: "Edited"})
    assert updated.message == "Edited"
    assert {:ok, _} = Rooms.delete_message(c.member, updated)
    assert Rooms.list_messages(c.owner, c.room) == []
  end

  test "inaccessible and malformed reads do not expose records", c do
    {:ok, message} = Rooms.create_message(c.member, c.room, %{message: "Hello"})
    assert {:error, :not_found} = Rooms.get_room(c.outsider, c.room.id)
    assert {:error, :not_found} = Rooms.get_room(c.owner, "bad")
    assert {:error, :not_found} = Rooms.get_message(c.outsider, message.id)
    assert {:error, :not_found} = Rooms.list_rooms(c.outsider, c.community)
    assert {:error, :not_found} = Rooms.list_messages(c.outsider, c.room)
    assert {:error, :unauthorized} = Rooms.create_message(c.outsider, c.room, %{message: "X"})
    assert {:error, :unauthorized} = Rooms.update_room(c.outsider, c.room, %{name: "X"})
    assert {:ok, _} = Communities.remove_member(c.owner, c.membership)
    assert {:error, :not_found} = Rooms.get_room(c.member, c.room.id)
    assert {:error, :unauthorized} = Rooms.delete_message(c.member, message)
    assert {:ok, _} = Communities.delete_community(c.owner, c.community)
    assert {:error, :not_found} = Rooms.get_room(c.owner, c.room.id)
    assert {:error, :not_found} = Rooms.get_message(c.owner, message.id)
  end

  test "validates content and ignores forged ownership", c do
    assert {:error, changeset} = Rooms.create_room(c.owner, c.community, %{name: nil})
    assert %{name: ["can't be blank"]} = errors_on(changeset)
    assert {:error, changeset} = Rooms.create_message(c.member, c.room, %{message: " "})
    assert %{message: ["can't be blank"]} = errors_on(changeset)

    assert {:ok, room} =
             Rooms.create_room(c.owner, c.community, %{name: "Other", community_id: -1})

    assert room.community_id == c.community.id
    assert Rooms.change_room(c.owner, %Room{community_id: c.community.id}, %{name: "New"}).valid?
    assert Rooms.change_message(c.member, %Message{room_id: c.room.id}, %{message: "New"}).valid?
  end

  test "deleting a room cascades to its messages", c do
    {:ok, message} = Rooms.create_message(c.member, c.room, %{message: "Hello"})
    assert {:ok, _} = Rooms.delete_room(c.owner, c.room)
    refute Repo.get(Message, message.id)
  end
end
