defmodule ArcanumWeb.PageController do
  use ArcanumWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def redirect_root(conn, _params) do
    conn
    |> Phoenix.Controller.redirect(to: "/communities")
    |> Plug.Conn.halt()
  end
end
