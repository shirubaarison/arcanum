defmodule ArcanumWeb.BackNavigationTest do
  use ArcanumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Arcanum.AccountsFixtures

  alias Arcanum.Accounts.Scope
  alias Arcanum.{Communities, Rooms}

  test "back controls use the history hook and retain direct-visit fallbacks", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)
    conn = log_in_user(conn, user)
    {:ok, community} = Communities.create_community(scope, %{name: "Navigation"})
    {:ok, room} = Rooms.create_room(scope, community, %{name: "General"})
    {:ok, post} = Communities.create_post(scope, community, %{title: "A post", body: "Hello"})

    for {path, id, fallback} <- [
          {~p"/#{user.username}", "profile-back", ~p"/communities"},
          {~p"/users/settings", "settings-back", ~p"/communities"},
          {~p"/communities/#{community}", "community-back", ~p"/communities"},
          {~p"/communities/#{community}/edit", "community-settings-back",
           ~p"/communities/#{community}"},
          {~p"/communities/#{community}/posts/#{post}", "post-back",
           ~p"/communities/#{community}"},
          {~p"/communities/#{community}/rooms/#{room.id}", "back-community",
           ~p"/communities/#{community}"}
        ] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "##{id}[phx-hook='HistoryBack'][href='#{fallback}']", "Back")
    end
  end
end
