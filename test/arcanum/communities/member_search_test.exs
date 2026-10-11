defmodule Arcanum.Communities.MemberSearchTest do
  use Arcanum.DataCase, async: true

  import Arcanum.AccountsFixtures
  alias Arcanum.Communities

  setup do
    scope = user_scope_fixture()
    {:ok, community} = Communities.create_community(scope, %{name: "Private"})
    %{scope: scope, community: community}
  end

  test "searches usernames case-insensitively, excludes members and exposes no email", context do
    %{scope: scope, community: community} = context
    candidate = user_fixture(%{username: "alpha_one"})
    user_fixture(%{username: "alphaone"})

    assert {:ok, [%{id: id, username: "alpha_one"} = result]} =
             Communities.search_available_users(scope, community, " ALPHA_ ")

    assert id == candidate.id
    assert Enum.sort(Map.keys(result)) == [:id, :username]
    assert {:ok, []} = Communities.search_available_users(scope, community, "%")
    assert {:ok, member} = Communities.add_member_by_id(scope, community, candidate.id)
    assert member.role == :member
    assert {:ok, []} = Communities.search_available_users(scope, community, "alpha_")

    assert {:error, %Ecto.Changeset{}} =
             Communities.add_member_by_id(scope, community, candidate.id)

    assert {:error, :user_not_found} = Communities.add_member_by_id(scope, community, -1)
  end

  test "limits the initial account list", %{scope: scope, community: community} do
    for _ <- 1..21, do: unconfirmed_user_fixture()
    assert {:ok, users} = Communities.search_available_users(scope, community)
    assert length(users) == 20
    refute Enum.any?(users, &(&1.id == scope.user.id))
  end

  test "only owners and admins can search and add accounts", context do
    %{scope: owner, community: community} = context
    member = user_scope_fixture()
    outsider = user_scope_fixture()
    {:ok, membership} = Communities.add_member(owner, community, member.user)

    for scope <- [member, outsider] do
      assert {:error, :unauthorized} = Communities.search_available_users(scope, community)

      assert {:error, :unauthorized} =
               Communities.add_member_by_id(scope, community, outsider.user.id)
    end

    {:ok, _} = Communities.update_membership(owner, membership, %{role: :admin})
    assert {:ok, _} = Communities.search_available_users(member, community)
    assert {:ok, added} = Communities.add_member_by_id(member, community, outsider.user.id)
    assert added.role == :member
    {:ok, _} = Communities.delete_community(owner, community)
    assert {:error, :unauthorized} = Communities.search_available_users(owner, community)
  end
end
