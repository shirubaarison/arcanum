defmodule ArcanumWeb.RoomLiveTest do
  use ArcanumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Arcanum.AccountsFixtures

  alias Arcanum.Accounts.Scope
  alias Arcanum.{Communities, Rooms}

  setup %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)
    owner = user_scope_fixture()
    {:ok, community} = Communities.create_community(owner, %{name: "Chat"})
    {:ok, membership} = Communities.add_member(owner, community, user)
    {:ok, room} = Rooms.create_room(owner, community, %{name: "General"})

    %{
      conn: log_in_user(conn, user),
      scope: scope,
      owner: owner,
      community: community,
      room: room,
      membership: membership
    }
  end

  test "community room links open a simple chat without avatars", c do
    {:ok, view, _} = live(c.conn, ~p"/communities/#{c.community}")
    view |> element("#room-link-#{c.room.id}") |> render_click()
    assert_redirect(view, ~p"/communities/#{c.community}/rooms/#{c.room.id}")
    {:ok, chat, _} = live(c.conn, ~p"/communities/#{c.community}/rooms/#{c.room.id}")
    assert has_element?(chat, "#room-name", "General")
    assert has_element?(chat, "#room-link-#{c.room.id}[aria-current='page']")

    assert has_element?(
             chat,
             "#room-users-#{c.room.id} #room-user-#{c.room.id}-#{c.scope.user.id}",
             c.scope.user.username
           )

    assert has_element?(chat, "#message-form")

    assert has_element?(
             chat,
             "#message-form #send-message[aria-label='Send message'] .hero-paper-airplane"
           )

    assert has_element?(chat, "#messages-empty")
    refute has_element?(chat, "#chatroom img")
    refute has_element?(chat, "#new-room")
  end

  test "chat renders only the community navbar", c do
    conn = get(c.conn, ~p"/communities/#{c.community}/rooms/#{c.room.id}")
    document = conn |> html_response(200) |> LazyHTML.from_document()
    assert LazyHTML.query(document, "nav[aria-label='Communities']") |> LazyHTML.to_html() != ""
    assert LazyHTML.query(document, "#current-username") |> LazyHTML.to_html() == ""
  end

  test "members send messages, validate blanks and see persisted history", c do
    {:ok, view, _} = live(c.conn, ~p"/communities/#{c.community}/rooms/#{c.room.id}")
    view |> form("#message-form", message: %{message: ""}) |> render_change()
    view |> form("#message-form", message: %{message: ""}) |> render_submit()
    assert Rooms.list_messages(c.scope, c.room) == []
    view |> form("#message-form", message: %{message: "Hello everyone"}) |> render_submit()
    [message] = Rooms.list_messages(c.scope, c.room)
    assert message.user_id == c.scope.user.id
    assert has_element?(view, "#message-user-#{message.id}", c.scope.user.username)
    assert has_element?(view, "#message-body-#{message.id}", "Hello everyone")
    assert has_element?(view, "#message-form textarea", "")
    {:ok, other_view, _} = live(c.conn, ~p"/communities/#{c.community}/rooms/#{c.room.id}")
    assert has_element?(other_view, "#messages-#{message.id}")
  end

  test "messages appear live for another room viewer", c do
    :ok = Rooms.subscribe_rooms(c.scope, c.community)
    {:ok, view, _} = live(c.conn, ~p"/communities/#{c.community}/rooms/#{c.room.id}")
    {:ok, message} = Rooms.create_message(c.owner, c.room, %{message: "Live message"})
    assert_receive {:room_message_changed, _id}
    assert has_element?(view, "#message-body-#{message.id}", "Live message")
  end

  test "presence shows up in the community sidebar and is removed on exit", c do
    :ok = Rooms.subscribe_rooms(c.scope, c.community)
    {:ok, community_view, _} = live(c.conn, ~p"/communities/#{c.community}")
    {:ok, chat, _} = live(c.conn, ~p"/communities/#{c.community}/rooms/#{c.room.id}")
    assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff", payload: %{joins: joins}}
    assert Map.has_key?(joins, to_string(c.scope.user.id))
    assert has_element?(community_view, "#room-user-#{c.room.id}-#{c.scope.user.id}")

    ref = Process.monitor(chat.pid)
    GenServer.stop(chat.pid, :normal)
    assert_receive {:DOWN, ^ref, :process, _pid, :normal}
    assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff", payload: %{leaves: leaves}}
    assert Map.has_key?(leaves, to_string(c.scope.user.id))
    refute has_element?(community_view, "#room-user-#{c.room.id}-#{c.scope.user.id}")
  end

  test "outsiders, invalid room IDs and wrong communities are rejected", c do
    outsider = log_in_user(build_conn(), user_fixture())
    {:ok, other} = Communities.create_community(c.scope, %{name: "Other"})

    for {conn, path} <- [
          {outsider, ~p"/communities/#{c.community}/rooms/#{c.room.id}"},
          {c.conn, ~p"/communities/#{c.community}/rooms/bad"},
          {c.conn, ~p"/communities/#{other}/rooms/#{c.room.id}"}
        ] do
      assert {:error, {:live_redirect, %{to: "/communities"}}} = live(conn, path)
    end

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(build_conn(), ~p"/communities/#{c.community}/rooms/#{c.room.id}")
  end

  test "removed members lose chat access", c do
    {:ok, view, _} = live(c.conn, ~p"/communities/#{c.community}/rooms/#{c.room.id}")
    {:ok, _} = Communities.remove_member(c.owner, c.membership)
    assert_redirect(view, ~p"/communities")
    assert Rooms.list_messages(c.owner, c.room) == []
  end
end
