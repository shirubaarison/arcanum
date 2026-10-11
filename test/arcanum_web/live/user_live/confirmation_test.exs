defmodule ArcanumWeb.UserLive.ConfirmationTest do
  use ArcanumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Arcanum.AccountsFixtures

  alias Arcanum.Accounts

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), confirmed_user: user_fixture()}
  end

  describe "Confirm user" do
    test "activation checkbox controls the persistent cookie", %{conn: conn} do
      for remember <- [true, false] do
        user = unconfirmed_user_fixture()
        {token, _} = generate_user_magic_link_token(user)
        {:ok, view, _} = live(conn, ~p"/users/log-in/#{token}")

        activation =
          form(view, "#confirmation_form",
            user: %{
              password: valid_user_password(),
              password_confirmation: valid_user_password(),
              token: token,
              remember_me: remember
            }
          )

        render_submit(activation)
        response = follow_trigger_action(activation, conn)
        assert Accounts.get_user!(user.id).confirmed_at
        assert Map.has_key?(response.resp_cookies, "_arcanum_web_user_remember_me") == remember
      end
    end

    test "activation rejects missing or mismatched passwords", %{
      conn: conn,
      unconfirmed_user: user
    } do
      {token, _} = generate_user_magic_link_token(user)
      {:ok, view, _} = live(conn, ~p"/users/log-in/#{token}")

      view
      |> form("#confirmation_form",
        user: %{password: valid_user_password(), password_confirmation: "different"}
      )
      |> render_submit()

      refute has_element?(view, "#confirmation_form[phx-trigger-action]")
      assert has_element?(view, "#confirmation_form", "does not match password")
      refute Accounts.get_user!(user.id).confirmed_at

      response = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})
      assert redirected_to(response) == ~p"/users/log-in"
      refute get_session(response, :user_token)
      refute Accounts.get_user!(user.id).confirmed_at
      assert Accounts.get_user_by_magic_link_token(token)
    end

    test "renders confirmation page for unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, view, _html} = live(conn, ~p"/users/log-in/#{token}")
      assert has_element?(view, "#confirmation-page")
      assert has_element?(view, "#confirmation_form input[name='user[password]'].community-input")
      assert has_element?(view, "#activate-remember[type=checkbox]")
      assert has_element?(view, "#activate-submit.community-button")
    end

    test "renders login page for confirmed user", %{conn: conn, confirmed_user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, view, _html} = live(conn, ~p"/users/log-in/#{token}")
      refute has_element?(view, "#confirmation_form")
      assert has_element?(view, "#confirm-login-remember[type=checkbox]")
      assert has_element?(view, "#confirm-login.community-button")
    end

    test "renders login page for already logged in user", %{conn: conn, confirmed_user: user} do
      conn = log_in_user(conn, user)

      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, _lv, html} = live(conn, ~p"/users/log-in/#{token}")
      refute html =~ "Confirm my account"
      assert html =~ "Log in"
    end

    test "confirms the given token once", %{conn: conn, unconfirmed_user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in/#{token}")

      form =
        form(lv, "#confirmation_form", %{
          "user" => %{
            "token" => token,
            "password" => valid_user_password(),
            "password_confirmation" => valid_user_password()
          }
        })

      render_submit(form)

      conn = follow_trigger_action(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "User confirmed successfully"

      assert Accounts.get_user!(user.id).confirmed_at
      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
      # we are logged in now
      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # log out, new conn
      conn = build_conn()

      {:ok, _lv, html} =
        live(conn, ~p"/users/log-in/#{token}")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Magic link is invalid or it has expired"
    end

    test "logs confirmed user in without changing confirmed_at", %{
      conn: conn,
      confirmed_user: user
    } do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in/#{token}")

      form = form(lv, "#login_form", %{"user" => %{"token" => token}})
      render_submit(form)

      conn = follow_trigger_action(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Welcome back!"

      assert Accounts.get_user!(user.id).confirmed_at == user.confirmed_at

      # log out, new conn
      conn = build_conn()

      {:ok, _lv, html} =
        live(conn, ~p"/users/log-in/#{token}")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Magic link is invalid or it has expired"
    end

    test "raises error for invalid token", %{conn: conn} do
      {:ok, _lv, html} =
        live(conn, ~p"/users/log-in/invalid-token")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Magic link is invalid or it has expired"
    end
  end
end
