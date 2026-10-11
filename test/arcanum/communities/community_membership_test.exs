defmodule Arcanum.Communities.CommunityMembershipTest do
  use Arcanum.DataCase, async: true

  import Arcanum.AccountsFixtures

  alias Arcanum.Communities.{Community, CommunityMembership}

  setup do
    community = %Community{} |> Community.changeset(%{name: "Elixir"}) |> Repo.insert!()
    user = unconfirmed_user_fixture()
    membership = %CommunityMembership{community_id: community.id, user_id: user.id}

    %{community: community, user: user, membership: membership}
  end

  test "defaults to member and exposes community members", context do
    membership = context.membership |> CommunityMembership.changeset(%{}) |> Repo.insert!()

    assert membership.role == :member
    assert %DateTime{} = membership.inserted_at
    assert %DateTime{} = membership.updated_at
    community = Repo.preload(context.community, :members)
    assert Enum.map(community.members, & &1.id) == [context.user.id]
  end

  test "accepts owner and admin roles", %{membership: membership} do
    for role <- [:owner, :admin] do
      changeset = CommunityMembership.changeset(membership, %{role: role})
      assert changeset.valid?
      assert get_field(changeset, :role) == role
    end
  end

  test "rejects unknown roles", %{membership: membership} do
    changeset = CommunityMembership.changeset(membership, %{role: "superuser"})
    assert %{role: ["is invalid"]} = errors_on(changeset)
  end

  test "requires community and user" do
    changeset = CommunityMembership.changeset(%CommunityMembership{}, %{})
    assert %{community_id: ["can't be blank"], user_id: ["can't be blank"]} = errors_on(changeset)
  end

  test "does not accept association IDs from attributes", %{membership: membership} do
    changeset = CommunityMembership.changeset(membership, %{community_id: 0, user_id: 0})
    assert get_field(changeset, :community_id) == membership.community_id
    assert get_field(changeset, :user_id) == membership.user_id
  end

  test "prevents duplicate memberships", %{membership: membership} do
    membership |> CommunityMembership.changeset(%{}) |> Repo.insert!()

    assert {:error, changeset} =
             membership |> CommunityMembership.changeset(%{}) |> Repo.insert()

    assert %{community_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "requires existing foreign keys", %{membership: membership} do
    for field <- [:community_id, :user_id] do
      invalid = Map.put(membership, field, -1)
      assert {:error, changeset} = invalid |> CommunityMembership.changeset(%{}) |> Repo.insert()
      assert errors_on(changeset)[field] == ["does not exist"]
    end
  end
end
