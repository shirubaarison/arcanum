defmodule ArcanumWeb.DevMailboxTest do
  use ArcanumWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Arcanum.AccountsFixtures
  alias Plug.Swoosh.MailboxPreview
  alias Swoosh.Adapters.Local.Storage.Memory

  setup do
    previous = Application.fetch_env!(:arcanum, Arcanum.Mailer)

    Application.put_env(:arcanum, Arcanum.Mailer,
      adapter: Swoosh.Adapters.Local,
      storage_driver: Memory
    )

    on_exit(fn -> Application.put_env(:arcanum, Arcanum.Mailer, previous) end)
    :ok
  end

  test "registration email is delivered to the local mailbox preview", %{conn: conn} do
    attrs = valid_user_attributes()
    {:ok, view, _} = live(conn, ~p"/users/register")
    view |> form("#registration_form", user: attrs) |> render_submit()
    assert_redirect(view, ~p"/users/log-in")

    email = Enum.find(Memory.all(), &({"", attrs.email} in &1.to))
    assert email.subject == "Confirmation instructions"
    id = email.headers["Message-ID"]

    preview =
      MailboxPreview.call(
        Plug.Test.conn(:get, "/#{id}"),
        MailboxPreview.init([])
      )

    assert preview.status == 200
    document = preview.resp_body |> IO.iodata_to_binary() |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#email-details__subject") |> LazyHTML.text() =~
             "Confirmation instructions"

    assert document |> LazyHTML.query("#text-body-content") |> LazyHTML.text() =~
             "/users/log-in/"
  end

  test "login emails reach the mailbox for registered users only", %{conn: conn} do
    user = user_fixture()
    {:ok, view, _} = live(conn, ~p"/users/log-in")
    view |> form("#login_form_magic", user: %{email: user.email}) |> render_submit()

    assert Enum.any?(
             Memory.all(),
             &(&1.subject == "Log in instructions" and {"", user.email} in &1.to)
           )

    missing = unique_user_email()
    {:ok, view, _} = live(conn, ~p"/users/log-in")
    view |> form("#login_form_magic", user: %{email: missing}) |> render_submit()
    refute Enum.any?(Memory.all(), &({"", missing} in &1.to))
  end
end
