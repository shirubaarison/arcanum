defmodule ArcanumWeb.ErrorHTMLTest do
  use ArcanumWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    document =
      ArcanumWeb.ErrorHTML
      |> render_to_string("404", "html", [])
      |> LazyHTML.from_document()

    assert LazyHTML.query(document, "#not-found") |> Enum.count() == 1
    assert LazyHTML.query(document, "#not-found-home[href='/communities']") |> Enum.count() == 1
    assert LazyHTML.query(document, "link[href='/assets/css/app.css']") |> Enum.count() == 1
  end

  test "renders 500.html" do
    assert render_to_string(ArcanumWeb.ErrorHTML, "500", "html", []) == "Internal Server Error"
  end
end
