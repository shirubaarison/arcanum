defmodule ArcanumWeb.CommunityRoomsLiveTest do
  use ArcanumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Arcanum.AccountsFixtures

  alias Arcanum.Accounts.Scope
  alias Arcanum.{Communities, Rooms}

  setup %{conn: conn} do
    user = user_fixture()
    owner = user_scope_fixture()
    {:ok, community} = Communities.create_community(owner, %{name: "Room community"})

    %{
      conn: log_in_user(conn, user),
      scope: Scope.for_user(user),
      owner: owner,
      community: community
    }
  end

  test "members see community rooms without creation controls", c do
    {:ok, _} = Communities.add_member(c.owner, c.community, c.scope.user)
    {:ok, room} = Rooms.create_room(c.owner, c.community, %{name: "General"})
    {:ok, other} = Communities.create_community(c.owner, %{name: "Other"})
    {:ok, hidden_room} = Rooms.create_room(c.owner, other, %{name: "Hidden"})
    {:ok, view, _} = live(c.conn, ~p"/communities/#{c.community}")

    assert has_element?(view, "#rooms-sidebar #rooms-#{room.id}", "General")
    refute has_element?(view, "#rooms-#{hidden_room.id}")
    refute has_element?(view, "#new-room")
    refute has_element?(view, "#room-form")

    render_click(view, "save_room", %{"room" => %{"name" => "Forged"}})
    assert_patch(view, ~p"/communities/#{c.community}")
    assert [%{id: id}] = Rooms.list_rooms(c.scope, c.community)
    assert id == room.id
  end

  test "admins validate and create rooms through the sidebar", c do
    {:ok, _} = Communities.add_member(c.owner, c.community, c.scope.user, %{role: :admin})
    {:ok, view, _} = live(c.conn, ~p"/communities/#{c.community}")
    assert has_element?(view, "#rooms-empty")
    view |> element("#new-room") |> render_click()
    assert_patch(view, ~p"/communities/#{c.community}/rooms/new")
    assert has_element?(view, "#room-form")

    view |> form("#room-form", room: %{name: ""}) |> render_change()
    assert has_element?(view, "#room-form [name='room[name]']")
    view |> form("#room-form", room: %{name: ""}) |> render_submit()
    assert Rooms.list_rooms(c.scope, c.community) == []

    view |> form("#room-form", room: %{name: "General"}) |> render_submit()
    assert_patch(view, ~p"/communities/#{c.community}")
    [room] = Rooms.list_rooms(c.scope, c.community)
    assert has_element?(view, "#rooms-sidebar #rooms-#{room.id}", "General")
    refute has_element?(view, "#room-form")
    assert has_element?(view, "#new-post")
  end

  test "owners can create rooms and cancel without saving", c do
    conn = log_in_user(build_conn(), c.owner.user)
    {:ok, view, _} = live(conn, ~p"/communities/#{c.community}/rooms/new")
    assert has_element?(view, "#room-form")
    view |> element("#cancel-room") |> render_click()
    assert_patch(view, ~p"/communities/#{c.community}")
    assert Rooms.list_rooms(c.owner, c.community) == []
    assert has_element?(view, "#new-room")
  end

  test "members cannot open the creation route", c do
    {:ok, _} = Communities.add_member(c.owner, c.community, c.scope.user)

    assert {:error, {:live_redirect, %{to: path}}} =
             live(c.conn, ~p"/communities/#{c.community}/rooms/new")

    assert path == ~p"/communities/#{c.community}"
  end

  test "creation rechecks permissions after demotion", c do
    {:ok, membership} =
      Communities.add_member(c.owner, c.community, c.scope.user, %{role: :admin})

    {:ok, view, _} = live(c.conn, ~p"/communities/#{c.community}/rooms/new")
    {:ok, _} = Communities.update_membership(c.owner, membership, %{role: :member})
    render_click(view, "save_room", %{"room" => %{"name" => "Denied"}})
    assert_patch(view, ~p"/communities/#{c.community}")
    assert Rooms.list_rooms(c.owner, c.community) == []
    refute has_element?(view, "#new-room")
  end

  test "outsiders and anonymous visitors cannot open creation", c do
    assert {:error, {:live_redirect, %{to: "/communities"}}} =
             live(c.conn, ~p"/communities/#{c.community}/rooms/new")

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(build_conn(), ~p"/communities/#{c.community}/rooms/new")
  end
end
