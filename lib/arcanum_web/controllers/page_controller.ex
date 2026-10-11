defmodule ArcanumWeb.PageController do
  use ArcanumWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
