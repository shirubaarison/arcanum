defmodule ArcanumWeb.LocalTimeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias ArcanumWeb.CoreComponents

  test "timestamps include UTC machine data, a readable fallback, and a local-time hook" do
    timestamp = ~U[2026-01-15 01:30:00Z]

    document =
      render_component(&CoreComponents.local_time/1, id: "timestamp", value: timestamp)
      |> LazyHTML.from_fragment()

    assert Enum.count(LazyHTML.query(document, "time#timestamp[datetime='2026-01-15T01:30:00Z']")) ==
             1

    assert Enum.count(LazyHTML.query(document, "#timestamp[data-utc='2026-01-15T01:30:00Z']")) ==
             1

    assert Enum.count(
             LazyHTML.query(document, "#timestamp[phx-hook='LocalTime'][phx-update='ignore']")
           ) == 1

    assert LazyHTML.text(document) =~ "Jan 15, 2026, 01:30 UTC"
  end
end
