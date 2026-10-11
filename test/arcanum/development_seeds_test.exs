defmodule Arcanum.DevelopmentSeedsTest do
  use Arcanum.DataCase, async: true

  import Arcanum.AccountsFixtures

  alias Arcanum.Accounts
  alias Arcanum.Accounts.{Scope, User}
  alias Arcanum.Communities
  alias Arcanum.Communities.{Comment, CommentVote, Community, CommunityMembership, Post, PostVote}
  alias Arcanum.DevelopmentSeeds

  test "creates confirmed demo accounts and realistic private community data" do
    %{users: users, communities: communities} = DevelopmentSeeds.run()
    assert map_size(users) == 4
    assert length(communities) == 3

    for {_name, user} <- users do
      assert user.confirmed_at
      assert User.valid_password?(user, "arcanum-demo-password")
    end

    assert Repo.aggregate(CommunityMembership, :count) == 7
    assert Repo.aggregate(Post, :count) == 6
    assert Repo.aggregate(Comment, :count) == 8
    assert Repo.aggregate(PostVote, :count) == 7
    assert Repo.aggregate(CommentVote, :count) == 8
    assert Enum.any?(Repo.all(PostVote), &(&1.value == -1))

    alice = Scope.for_user(users["alice"])
    carol = Scope.for_user(users["carol"])
    dave = Scope.for_user(users["dave"])
    assert length(Communities.list_user_posts(alice, users["alice"])) == 2
    assert length(Communities.list_user_posts(carol, users["alice"])) == 1
    assert Communities.list_user_posts(dave, users["alice"]) == []
    assert Communities.user_karma(alice, users["alice"]) > 0
    assert Enum.any?(Repo.all(Comment), &(not is_nil(&1.parent_id)))
  end

  test "running twice preserves records and timestamps without duplicates" do
    DevelopmentSeeds.run()
    before = snapshot()
    DevelopmentSeeds.run()
    assert snapshot() == before
  end

  test "existing passwords, edited content, roles and votes are not reset" do
    %{users: users, communities: [commons | _]} = DevelopmentSeeds.run()
    alice = Scope.for_user(users["alice"])
    bob = Scope.for_user(users["bob"])

    {:ok, {updated_user, _}} =
      Accounts.update_user_password(alice.user, %{password: "my-changed-password"})

    welcome = Repo.get_by!(Post, community_id: commons.id, author_id: alice.user.id)
    {:ok, post} = welcome |> Post.changeset(%{body: "Edited body"}) |> Repo.update()
    membership = Repo.get_by!(CommunityMembership, community_id: commons.id, user_id: bob.user.id)
    {:ok, _} = Communities.update_membership(alice, membership, %{role: :member})
    {:ok, _} = Communities.vote_post(bob, post, -1)
    before = snapshot()

    DevelopmentSeeds.run()
    assert snapshot() == before
    assert User.valid_password?(Accounts.get_user!(updated_user.id), "my-changed-password")
  end

  test "identity collisions roll back seeds rather than adopting unrelated accounts" do
    existing = user_fixture(%{username: "demo_bob", email: "not-a-demo@example.com"})
    before = snapshot()

    assert_raise RuntimeError, ~r/conflicts with an existing account/, fn ->
      DevelopmentSeeds.run()
    end

    assert snapshot() == before
    assert Accounts.get_user!(existing.id).email == "not-a-demo@example.com"
  end

  test "community ownership collisions roll back without changing user data" do
    owner = user_scope_fixture()
    {:ok, _} = Communities.create_community(owner, %{name: "Demo Commons"})
    before = snapshot()

    assert_raise RuntimeError, ~r/different owner/, fn -> DevelopmentSeeds.run() end
    assert snapshot() == before
  end

  test "the seed entry point refuses the non-development test environment" do
    before = snapshot()

    assert_raise RuntimeError, ~r/must run with MIX_ENV=dev/, fn ->
      Code.eval_file("priv/repo/seeds.exs")
    end

    assert snapshot() == before
  end

  defp snapshot do
    Map.new(
      [User, Community, CommunityMembership, Post, Comment, PostVote, CommentVote],
      fn schema ->
        {schema, Repo.all(from record in schema, order_by: record.id)}
      end
    )
  end
end
