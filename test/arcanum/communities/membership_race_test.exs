defmodule Arcanum.Communities.MembershipRaceTest do
  use Arcanum.RaceCase, async: false

  alias Arcanum.Communities
  alias Arcanum.Communities.{CommunityMembership, Post, PostVote}

  test "membership removal racing with posting respects whichever operation commits first",
       context do
    %{owner: owner, member: member, membership: membership, community: community} = context

    [removal, posting] =
      race([
        fn -> Communities.remove_member(owner, membership) end,
        fn ->
          Communities.create_post(member, community, %{title: "Concurrent post", body: "Text"})
        end
      ])

    assert {:ok, %CommunityMembership{}} = removal
    assert match?({:ok, %Post{}}, posting) or posting == {:error, :unauthorized}

    unboxed(fn ->
      assert {:error, :not_found} = Communities.get_community(member, community.id)

      assert {:error, :unauthorized} =
               Communities.create_post(member, community, %{title: "Too late", body: "Text"})

      count =
        Repo.aggregate(
          from(p in Post,
            where: p.community_id == ^community.id and p.author_id == ^member.user.id
          ),
          :count
        )

      assert count == if(match?({:ok, _}, posting), do: 1, else: 0)
    end)
  end

  test "membership removal racing with voting cannot create a vote after access is revoked",
       context do
    %{owner: owner, member: member, membership: membership, post: post} = context

    [removal, voting] =
      race([
        fn -> Communities.remove_member(owner, membership) end,
        fn -> Communities.vote_post(member, post, 1) end
      ])

    assert {:ok, %CommunityMembership{}} = removal
    assert match?({:ok, %PostVote{}}, voting) or voting == {:error, :unauthorized}

    unboxed(fn ->
      assert {:error, :unauthorized} = Communities.vote_post(member, post, -1)

      votes =
        Repo.all(
          from v in PostVote, where: v.post_id == ^post.id and v.user_id == ^member.user.id
        )

      assert length(votes) == if(match?({:ok, _}, voting), do: 1, else: 0)
      assert Enum.all?(votes, &(&1.value == 1))
    end)
  end

  test "community deletion racing with posting blocks all subsequent participation", context do
    %{owner: owner, member: member, community: community} = context

    [deletion, posting] =
      race([
        fn -> Communities.delete_community(owner, community) end,
        fn ->
          Communities.create_post(member, community, %{title: "Concurrent post", body: "Text"})
        end
      ])

    assert {:ok, %{deleted_at: %DateTime{}}} = deletion
    assert match?({:ok, %Post{}}, posting) or posting == {:error, :unauthorized}

    unboxed(fn ->
      assert {:error, :not_found} = Communities.get_community(member, community.id)

      assert {:error, :unauthorized} =
               Communities.create_post(member, community, %{title: "Too late", body: "Text"})

      count =
        Repo.aggregate(
          from(p in Post,
            where: p.community_id == ^community.id and p.author_id == ^member.user.id
          ),
          :count
        )

      assert count == if(match?({:ok, _}, posting), do: 1, else: 0)
    end)
  end
end
