defmodule ArcanumWeb.FailureLogTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ArcanumWeb.FailureLog

  test "logs atom reasons" do
    assert capture_log(fn -> FailureLog.log("post lookup", :not_found) end) =~
             "post lookup failed: not_found"
  end

  test "validation logs omit submitted data and interpolated messages" do
    changeset =
      {%{}, %{password: :string}}
      |> Ecto.Changeset.cast(%{"password" => "secret-password"}, [:password])
      |> Ecto.Changeset.add_error(:password, "secret-password is invalid", validation: :length)

    log = capture_log(fn -> FailureLog.log("activation", changeset) end)
    assert log =~ "password: :length"
    refute log =~ "secret-password"
  end

  test "unknown provider errors never dump sensitive payloads" do
    log = capture_log(fn -> FailureLog.log("email delivery", %{token: "secret-token"}) end)
    assert log =~ "email delivery failed: unexpected error"
    refute log =~ "secret-token"
  end
end
