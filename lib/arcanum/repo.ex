defmodule Arcanum.Repo do
  use Ecto.Repo,
    otp_app: :arcanum,
    adapter: Ecto.Adapters.Postgres
end
