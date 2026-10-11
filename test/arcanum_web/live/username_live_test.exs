defmodule ArcanumWeb.UsernameLiveTest do
  use ArcanumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Arcanum.AccountsFixtures
  alias Arcanum.Accounts

  test "registration includes username validation", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/users/register")
    assert has_element?(view, "#registration-page")
    assert has_element?(view, "#registration_form .community-input")
    assert has_element?(view, "#create-account.community-button")
    assert has_element?(view, "#registration_form input[name='user[username]']")

    view
    |> form("#registration_form", user: %{email: unique_user_email(), username: "bad name"})
    |> render_change()

    assert has_element?(view, "#registration_form", "must start with a letter")
  end

  test "login uses the shared design with guest navigation", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/users/log-in")
    assert has_element?(view, "#login-page")
    assert has_element?(view, "#login_form_magic .community-input")
    assert has_element?(view, "#login_form_password .community-input")
    assert has_element?(view, "#login-with-email.community-button")
    assert has_element?(view, "header a[href='/users/register']")
    refute has_element?(view, "header a[href='/users/log-out']")
  end

  test "user changes their username in settings", %{conn: conn} do
    user = user_fixture()
    {:ok, view, _} = live(log_in_user(conn, user), ~p"/users/settings")
    assert has_element?(view, "#username-form")
    assert has_element?(view, "#account-settings")
    assert has_element?(view, "#username-form .community-input")
    assert has_element?(view, "#save-username.community-button")
    assert has_element?(view, "#email_form .community-input")
    assert has_element?(view, "#save-password.community-button")
    view |> form("#username-form", user: %{username: "new_username"}) |> render_submit()
    assert Accounts.get_user!(user.id).username == "new_username"
    assert has_element?(view, "#username-form input[value='new_username']")
    view |> form("#username-form", user: %{username: "no spaces"}) |> render_submit()
    assert Accounts.get_user!(user.id).username == "new_username"
    assert has_element?(view, "#username-form", "must start with a letter")
  end

  test "posts and comments show usernames rather than author emails", %{conn: conn} do
    scope = user_scope_fixture()
    {:ok, community} = Arcanum.Communities.create_community(scope, %{name: "Private"})

    {:ok, post} =
      Arcanum.Communities.create_post(scope, community, %{title: "Hello", body: "Text"})

    {:ok, comment} = Arcanum.Communities.create_comment(scope, post, %{body: "Comment"})

    {:ok, view, _} =
      live(log_in_user(conn, scope.user), ~p"/communities/#{community}/posts/#{post}")

    assert has_element?(view, "#comments-#{comment.id}", scope.user.username)
    refute has_element?(view, "#comments-#{comment.id}", scope.user.email)
  end
end
