defmodule Arcanum.Accounts.UsernamesTest do
  use Arcanum.DataCase, async: true

  import Arcanum.AccountsFixtures
  alias Arcanum.Accounts
  alias Arcanum.Accounts.{Scope, User}

  test "requires and normalizes usernames at registration" do
    assert {:error, changeset} = Accounts.register_user(%{email: unique_user_email()})
    assert %{username: ["can't be blank"]} = errors_on(changeset)
    assert {:ok, user} = Accounts.register_user(valid_user_attributes(username: "  Test_User  "))
    assert user.username == "test_user"
  end

  test "validates format and length" do
    for username <- ["ab", String.duplicate("a", 31), "1user", "two words", "user-name"] do
      assert {:error, changeset} =
               Accounts.register_user(valid_user_attributes(username: username))

      assert Map.has_key?(errors_on(changeset), :username)
    end
  end

  test "usernames are unique without regard to case" do
    user = user_fixture()

    assert {:error, changeset} =
             Accounts.register_user(valid_user_attributes(username: String.upcase(user.username)))

    assert %{username: ["has already been taken"]} = errors_on(changeset)

    assert {:error, changeset} =
             %User{}
             |> User.registration_changeset(valid_user_attributes(username: user.username),
               validate_unique: false
             )
             |> Repo.insert()

    assert %{username: ["has already been taken"]} = errors_on(changeset)
  end

  test "username updates only change the scoped caller and preserve email" do
    user = user_fixture()
    other = user_fixture()
    scope = Scope.for_user(user)

    assert {:ok, updated} =
             Accounts.update_user_username(scope, %{
               username: "Changed_User",
               id: other.id,
               email: other.email
             })

    assert updated.username == "changed_user"
    assert updated.email == user.email
    assert updated.id == user.id
    assert Accounts.get_user!(other.id).username == other.username
    assert {:error, changeset} = Accounts.update_user_username(scope, %{username: other.username})
    assert %{username: ["has already been taken"]} = errors_on(changeset)
  end
end
