defmodule ArcanumWeb.PageControllerTest do
  use ArcanumWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/communities"
  end
end
