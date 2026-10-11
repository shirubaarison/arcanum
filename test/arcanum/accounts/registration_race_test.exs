defmodule Arcanum.Accounts.RegistrationRaceTest do
  use Arcanum.RaceCase, async: false

  alias Arcanum.Accounts
  alias Arcanum.Accounts.User

  test "simultaneous registrations for the same username return one success", context do
    %{candidate: candidate, alternate_email: alternate_email} = context

    results =
      race([
        fn -> Accounts.register_user(candidate) end,
        fn -> Accounts.register_user(%{candidate | email: alternate_email}) end
      ])

    assert_single_registration(results, :username)

    unboxed(fn ->
      assert Repo.aggregate(from(u in User, where: u.username == ^candidate.username), :count) ==
               1
    end)
  end

  test "email uniqueness survives two changesets validated before either insert", context do
    candidate = context.candidate
    other_username = "#{candidate.username}_alt"

    operations =
      for attributes <- [candidate, %{candidate | username: other_username}] do
        {
          fn ->
            changeset = User.registration_changeset(%User{}, attributes)
            assert changeset.valid?
            changeset
          end,
          &Repo.insert/1
        }
      end

    assert_single_registration(race(operations), :email)

    unboxed(fn ->
      assert Repo.aggregate(from(u in User, where: u.email == ^candidate.email), :count) == 1
    end)
  end

  test "username uniqueness survives two changesets validated before either insert", context do
    %{candidate: candidate, alternate_email: alternate_email} = context

    operations =
      for attributes <- [candidate, %{candidate | email: alternate_email}] do
        {
          fn ->
            changeset = User.registration_changeset(%User{}, attributes)
            assert changeset.valid?
            changeset
          end,
          &Repo.insert/1
        }
      end

    assert_single_registration(race(operations), :username)
  end

  defp assert_single_registration(results, field) do
    assert Enum.count(results, &match?({:ok, %User{}}, &1)) == 1
    assert [{:error, changeset}] = Enum.filter(results, &match?({:error, _}, &1))
    assert Keyword.has_key?(changeset.errors, field)
    assert Arcanum.DataCase.errors_on(changeset)[field] == ["has already been taken"]
  end
end
