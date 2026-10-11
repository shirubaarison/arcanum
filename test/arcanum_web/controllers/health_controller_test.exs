defmodule ArcanumWeb.HealthControllerTest do
  use ArcanumWeb.ConnCase, async: true

  test "GET /health is a public JSON liveness check", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert json_response(conn, 200) == %{"status" => "ok"}
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert conn.resp_cookies == %{}
    refute Map.has_key?(conn.assigns, :current_scope)
  end

  test "HEAD /health returns a successful status without a response body", %{conn: conn} do
    conn = head(conn, ~p"/health")

    assert conn.status == 200
    assert conn.resp_body == ""
  end
end
