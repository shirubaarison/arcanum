defmodule Arcanum.CommunitiesTest do
  use Arcanum.DataCase, async: true

  import Arcanum.AccountsFixtures

  alias Arcanum.Accounts.Scope
  alias Arcanum.Communities
  alias Arcanum.Communities.{Community, CommunityMembership}

  setup do
    owner = unconfirmed_user_fixture()
    scope = Scope.for_user(owner)
    {:ok, community} = Communities.create_community(scope, %{name: "Elixir"})
    %{scope: scope, community: community, outsider: Scope.for_user(unconfirmed_user_fixture())}
  end

  test "creates an owner and rolls back invalid creation", %{scope: scope, community: community} do
    assert [%{role: :owner, user_id: user_id}] = Communities.list_memberships(scope, community)
    assert user_id == scope.user.id
    assert {:error, changeset} = Communities.create_community(scope, %{name: ""})
    assert %{name: ["can't be blank"]} = errors_on(changeset)
    assert Repo.aggregate(Community, :count) == 1
    assert Repo.aggregate(CommunityMembership, :count) == 1
  end

  test "scopes reads and rejects outsider mutations", context do
    %{scope: scope, community: community, outsider: outsider} = context
    assert Communities.list_communities(scope) == [community]
    assert Communities.list_communities(outsider) == []
    assert_raise Ecto.NoResultsError, fn -> Communities.get_community!(outsider, community.id) end
    assert {:error, :not_found} = Communities.list_memberships(outsider, community)

    assert {:error, :unauthorized} =
             Communities.update_community(outsider, community, %{name: "X"})

    assert {:error, :unauthorized} = Communities.delete_community(outsider, community)
    assert {:error, :unauthorized} = Communities.add_member(outsider, community, outsider.user)
  end

  test "updates and soft-deletes communities", %{scope: scope, community: community} do
    assert Communities.change_community(scope, community).valid?

    assert {:ok, updated} =
             Communities.update_community(scope, community, %{description: "Hello"})

    assert updated.description == "Hello"
    assert {:error, changeset} = Communities.update_community(scope, community, %{name: ""})
    refute changeset.valid?
    assert {:ok, deleted} = Communities.delete_community(scope, community)
    assert %DateTime{} = deleted.deleted_at
    assert Communities.list_communities(scope) == []
    assert_raise Ecto.NoResultsError, fn -> Communities.get_community!(scope, community.id) end
    assert {:error, :unauthorized} = Communities.update_community(scope, community, %{name: "X"})
    assert {:error, :unauthorized} = Communities.add_member(scope, community, scope.user)
    assert Repo.get!(Community, community.id)
  end

  test "manages memberships and validates duplicate additions", context do
    %{scope: scope, community: community, outsider: outsider} = context
    assert {:ok, member} = Communities.add_member(scope, community, outsider.user)
    assert member.role == :member
    assert Communities.get_community!(outsider, community.id) == community
    assert Enum.all?(Communities.list_memberships(scope, community), &Ecto.assoc_loaded?(&1.user))
    assert {:error, changeset} = Communities.add_member(scope, community, outsider.user)
    assert %{community_id: ["has already been taken"]} = errors_on(changeset)

    assert {:error, changeset} =
             Communities.add_member(scope, community, unconfirmed_user_fixture(), %{role: "bad"})

    assert %{role: ["is invalid"]} = errors_on(changeset)

    assert {:error, :unauthorized} =
             Communities.update_community(outsider, community, %{name: "X"})

    assert {:error, :unauthorized} = Communities.change_community(outsider, community)
    assert {:error, :unauthorized} = Communities.remove_member(outsider, member)
    assert {:ok, admin} = Communities.update_membership(scope, member, %{role: :admin})
    assert admin.role == :admin
    assert {:ok, _} = Communities.remove_member(scope, admin)
    assert Communities.list_communities(outsider) == []
  end

  test "admins manage members but cannot manage admins, owners or deletion", context do
    %{scope: scope, community: community, outsider: admin_scope} = context
    {:ok, admin} = Communities.add_member(scope, community, admin_scope.user, %{role: :admin})
    user = unconfirmed_user_fixture()
    assert {:ok, member} = Communities.add_member(admin_scope, community, user)
    assert {:ok, _} = Communities.update_community(admin_scope, community, %{name: "Updated"})
    assert {:ok, _} = Communities.update_membership(admin_scope, member, %{role: :member})

    assert {:error, :unauthorized} =
             Communities.update_membership(admin_scope, member, %{role: :admin})

    assert {:error, :unauthorized} = Communities.remove_member(admin_scope, admin)
    assert {:error, :unauthorized} = Communities.delete_community(admin_scope, community)

    assert {:error, :unauthorized} =
             Communities.add_member(admin_scope, community, unconfirmed_user_fixture(), %{
               role: :admin
             })

    owner = Repo.get_by!(CommunityMembership, community_id: community.id, user_id: scope.user.id)
    assert {:error, :unauthorized} = Communities.remove_member(scope, owner)
    assert {:error, :unauthorized} = Communities.update_membership(scope, owner, %{role: :member})

    assert {:error, :unauthorized} =
             Communities.add_member(scope, community, user, %{role: :owner})

    assert {:ok, _} = Communities.remove_member(admin_scope, member)
  end

  test "membership operations refetch persisted permissions and reject mismatched communities",
       context do
    %{scope: scope, community: community, outsider: outsider} = context
    {:ok, member} = Communities.add_member(scope, community, outsider.user)
    {:ok, other} = Communities.create_community(outsider, %{name: "Other"})
    forged = %{member | community_id: other.id, role: :owner}
    assert {:error, :unauthorized} = Communities.remove_member(outsider, forged)

    assert {:error, :unauthorized} =
             Communities.update_membership(outsider, forged, %{role: :admin})

    {:ok, admin} = Communities.update_membership(scope, member, %{role: :admin})
    {:ok, _} = Communities.update_membership(scope, admin, %{role: :member})

    assert {:error, :unauthorized} =
             Communities.add_member(outsider, community, unconfirmed_user_fixture())
  end
end
