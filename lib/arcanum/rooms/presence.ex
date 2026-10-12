defmodule Arcanum.Rooms.Presence do
  @moduledoc "Tracks community members currently viewing rooms."
  use Phoenix.Presence,
    otp_app: :arcanum,
    pubsub_server: Arcanum.PubSub
end
