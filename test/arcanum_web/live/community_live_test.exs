defmodule ArcanumWeb.CommunityLiveTest do
  use ArcanumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Arcanum.AccountsFixtures

  alias Arcanum.Accounts.Scope
  alias Arcanum.Communities

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), scope: Scope.for_user(user)}
  end

  test "requires login", %{conn: _conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/communities")
  end

  test "shows an empty state", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/communities")
    assert has_element?(view, "#communities-empty")
    assert has_element?(view, "#communities-empty a[href='/communities/new']")
  end

  test "admins can edit and manage members but cannot delete", %{conn: conn, scope: scope} do
    owner = user_scope_fixture()
    {:ok, community} = Communities.create_community(owner, %{name: "Admin access"})
    {:ok, admin} = Communities.add_member(owner, community, scope.user, %{role: :admin})
    {:ok, member} = Communities.add_member(owner, community, user_fixture())
    {:ok, view, _} = live(conn, ~p"/communities/#{community}")
    assert has_element?(view, "#community-form")
    assert has_element?(view, "#member-form")
    assert has_element?(view, "#remove-#{member.id}")
    refute has_element?(view, "#remove-#{admin.id}")
    refute has_element?(view, "#role-#{member.id}")
    refute has_element?(view, "#delete-community")
    render_click(view, "change_role", %{"id" => to_string(member.id), "role" => "admin"})

    assert Enum.find(Communities.list_memberships(owner, community), &(&1.id == member.id)).role ==
             :member
  end

  test "lists only the caller's communities", %{conn: conn, scope: scope} do
    {:ok, own} = Communities.create_community(scope, %{name: "Own"})
    {:ok, other} = Communities.create_community(user_scope_fixture(), %{name: "Other"})
    {:ok, view, _} = live(conn, ~p"/communities")
    assert has_element?(view, "#communities-#{own.id}")
    refute has_element?(view, "#communities-#{other.id}")
    refute has_element?(view, "#communities-empty:not(.hidden)")
  end

  test "creates and validates a community", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/communities/new")
    view |> form("#community-form", community: %{name: ""}) |> render_submit()
    assert has_element?(view, "#community-form [name='community[name]']")
    assert Communities.list_communities(scope) == []

    view
    |> form("#community-form", community: %{name: "New", description: "Hello"})
    |> render_submit()

    [community] = Communities.list_communities(scope)
    assert_redirect(view, ~p"/communities/#{community}")
  end

  test "owner edits, adds a member, changes roles and removes members", %{
    conn: conn,
    scope: scope
  } do
    {:ok, community} = Communities.create_community(scope, %{name: "Original"})
    user = user_fixture()
    {:ok, view, _} = live(conn, ~p"/communities/#{community}")
    view |> form("#community-form", community: %{name: "Updated"}) |> render_submit()
    assert has_element?(view, "#community-name", "Updated")
    view |> form("#member-form", member: %{email: "missing@example.com"}) |> render_submit()
    assert has_element?(view, "#member-form", "No registered user")
    view |> form("#member-form", member: %{email: user.email}) |> render_submit()
    member = Enum.find(Communities.list_memberships(scope, community), &(&1.user_id == user.id))
    assert has_element?(view, "#memberships-#{member.id}")
    view |> element("#role-#{member.id}") |> render_click()
    assert has_element?(view, "#memberships-#{member.id}", "admin")
    view |> element("#remove-#{member.id}") |> render_click()
    refute has_element?(view, "#memberships-#{member.id}")
  end

  test "members have read-only access and forged events are rejected", %{conn: conn, scope: scope} do
    owner = user_scope_fixture()
    {:ok, community} = Communities.create_community(owner, %{name: "Private"})
    {:ok, _} = Communities.add_member(owner, community, scope.user)
    {:ok, view, _} = live(conn, ~p"/communities/#{community}")
    assert has_element?(view, "#community-name")
    refute has_element?(view, "#community-form")
    refute has_element?(view, "#member-form")
    refute has_element?(view, "#delete-community")
    render_click(view, "save", %{"community" => %{"name" => "Forged"}})
    render_click(view, "delete")
    assert Communities.get_community!(owner, community.id).name == "Private"
  end

  test "owner can soft-delete", %{conn: conn, scope: scope} do
    {:ok, community} = Communities.create_community(scope, %{name: "Delete"})
    {:ok, view, _} = live(conn, ~p"/communities/#{community}")
    view |> element("#delete-community") |> render_click()
    assert_redirect(view, ~p"/communities")
    assert Communities.list_communities(scope) == []
  end

  test "outsiders cannot load a community", %{conn: conn} do
    {:ok, community} = Communities.create_community(user_scope_fixture(), %{name: "Hidden"})
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/communities/#{community}") end
  end
end
