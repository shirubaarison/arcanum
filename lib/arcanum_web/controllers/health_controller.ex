defmodule ArcanumWeb.HealthController do
  use ArcanumWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(%{status: "ok"})
  end
end
