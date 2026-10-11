defmodule Arcanum.RaceCase do
  @moduledoc "Committed, uniquely named fixtures for real PostgreSQL concurrency tests."
  use ExUnit.CaseTemplate

  import Arcanum.AccountsFixtures
  import Ecto.Query

  alias Arcanum.Accounts.{Scope, User}
  alias Arcanum.Communities
  alias Arcanum.Communities.Community
  alias Arcanum.RaceWorker
  alias Arcanum.Repo
  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Arcanum.RaceCase
      import Ecto.Query
      alias Arcanum.Repo
    end
  end

  setup do
    attributes = Enum.map(1..3, fn _ -> valid_user_attributes() end)
    candidate = valid_user_attributes()
    alternate_email = unique_user_email()
    emails = [candidate.email, alternate_email | Enum.map(attributes, & &1.email)]
    community_name = "Race #{System.unique_integer([:positive, :monotonic])}"

    # Unlike regular sandbox tests, these fixtures are committed. Delete only
    # this test's exact records, including any successful concurrent inserts.
    on_exit(fn ->
      unboxed(fn ->
        Repo.transaction(fn ->
          Repo.delete_all(from c in Community, where: c.name == ^community_name)
          Repo.delete_all(from u in User, where: u.email in ^emails)
        end)
      end)
    end)

    unboxed(fn ->
      {:ok, context} =
        Repo.transaction(fn ->
          [owner, member, other] = Enum.map(attributes, &unconfirmed_user_fixture/1)
          owner = Scope.for_user(owner)
          member = Scope.for_user(member)
          other = Scope.for_user(other)
          {:ok, community} = Communities.create_community(owner, %{name: community_name})
          {:ok, membership} = Communities.add_member(owner, community, member.user)
          {:ok, _} = Communities.add_member(owner, community, other.user)

          {:ok, post} =
            Communities.create_post(owner, community, %{title: "Race post", body: "Text"})

          {:ok, comment} = Communities.create_comment(owner, post, %{body: "Race comment"})

          %{
            owner: owner,
            member: member,
            other: other,
            membership: membership,
            community: community,
            post: post,
            comment: comment,
            candidate: candidate,
            alternate_email: alternate_email
          }
        end)

      context
    end)
  end

  def unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  @doc "Starts supervised workers, verifies separate PostgreSQL sessions, then releases them together."
  def race(operations) do
    workers = Enum.map(operations, &start_worker/1)

    backend_ids =
      for {pid, _ref} <- workers do
        assert_receive {:race_ready, ^pid, backend_id}, 15_000
        backend_id
      end

    assert length(Enum.uniq(backend_ids)) == length(workers)
    for {pid, _ref} <- workers, do: send(pid, :race_go)

    for {pid, ref} <- workers do
      assert_receive {:race_result, ^pid, result}, 15_000
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 15_000
      result
    end
  end

  defp start_worker(operation) when is_function(operation, 0) do
    start_worker({fn -> nil end, fn _ -> operation.() end})
  end

  defp start_worker({prepare, run}) do
    spec =
      Supervisor.child_spec(
        {RaceWorker, %{owner: self(), prepare: prepare, run: run}},
        id: make_ref()
      )

    pid = start_supervised!(spec)
    {pid, Process.monitor(pid)}
  end
end
