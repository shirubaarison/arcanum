defmodule Arcanum.Communities.NamesTest do
  use Arcanum.DataCase, async: true

  import Arcanum.AccountsFixtures

  alias Arcanum.Accounts
  alias Arcanum.Communities

  test "community names are trimmed and unique regardless of case" do
    scope = user_scope_fixture()
    {:ok, community} = Communities.create_community(scope, %{name: "  Elixir Club  "})
    assert community.name == "Elixir Club"
    assert Phoenix.Param.to_param(community) == "Elixir Club"

    assert {:error, changeset} =
             Communities.create_community(user_scope_fixture(), %{name: "elixir club"})

    assert %{name: ["has already been taken"]} = errors_on(changeset)

    {:ok, other} = Communities.create_community(scope, %{name: "Other"})

    assert {:error, changeset} =
             Communities.update_community(scope, other, %{name: "ELIXIR CLUB"})

    assert %{name: ["has already been taken"]} = errors_on(changeset)
  end

  test "name lookups remain membership scoped and exclude deleted communities" do
    scope = user_scope_fixture()
    {:ok, community} = Communities.create_community(scope, %{name: "Elixir Club"})
    assert {:ok, ^community} = Communities.get_community_by_name(scope, "elixir club")

    assert {:error, :not_found} =
             Communities.get_community_by_name(user_scope_fixture(), "Elixir Club")

    assert {:error, :not_found} = Communities.get_community_by_name(scope, "Unknown")
    {:ok, _} = Communities.delete_community(scope, community)
    assert {:error, :not_found} = Communities.get_community_by_name(scope, "Elixir Club")
  end

  test "community names that conflict with URL paths are rejected" do
    scope = user_scope_fixture()

    for name <- ["new", "NEW", "has/slash"] do
      assert {:error, changeset} = Communities.create_community(scope, %{name: name})
      assert Map.has_key?(errors_on(changeset), :name)
    end
  end

  test "usernames remain unique and cannot conflict with application routes" do
    user = user_fixture(%{username: "alice"})

    assert {:error, changeset} =
             Accounts.register_user(%{email: unique_user_email(), username: "ALICE"})

    assert %{username: ["has already been taken"]} = errors_on(changeset)

    for username <- ~w(communities users dev assets images live health) do
      assert {:error, changeset} =
               Accounts.update_user_username(user_scope_fixture(user), %{username: username})

      assert %{username: ["is reserved"]} = errors_on(changeset)
    end
  end
end
