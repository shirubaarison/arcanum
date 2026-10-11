defmodule Arcanum.Communities.NamesTest do
  use Arcanum.DataCase, async: true

  import Arcanum.AccountsFixtures

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
end
