defmodule Arcanum.RaceWorker do
  @moduledoc "Runs a gated operation on a separate, non-transactional sandbox connection."
  use GenServer, restart: :temporary

  alias Arcanum.Repo
  alias Ecto.Adapters.SQL.Sandbox

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @impl true
  def init(options), do: {:ok, options, {:continue, :run}}

  @impl true
  def handle_continue(:run, options) do
    result =
      Sandbox.unboxed_run(Repo, fn ->
        prepared = options.prepare.()
        %{rows: [[backend_id]]} = Repo.query!("SELECT pg_backend_pid()")
        send(options.owner, {:race_ready, self(), backend_id})

        receive do
          :race_go -> options.run.(prepared)
        after
          15_000 -> raise "Race worker did not receive its start signal"
        end
      end)

    send(options.owner, {:race_result, self(), result})
    {:stop, :normal, options}
  end
end
