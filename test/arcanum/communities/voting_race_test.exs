defmodule Arcanum.Communities.VotingRaceTest do
  use Arcanum.RaceCase, async: false

  alias Arcanum.Communities
  alias Arcanum.Communities.{CommentVote, PostVote}

  test "competing post votes from one user leave exactly one valid vote", context do
    %{member: member, post: post, community: community} = context

    results =
      race(
        Enum.map([1, -1, 1, -1], fn value ->
          fn -> Communities.vote_post(member, post, value) end
        end)
      )

    assert Enum.all?(results, &match?({:ok, %PostVote{}}, &1))

    unboxed(fn ->
      assert [vote] = Repo.all(from v in PostVote, where: v.post_id == ^post.id)
      assert vote.value in [-1, 1]
      assert {:ok, current} = Communities.get_post(member, community, post.id)
      assert current.score == vote.value
      assert current.my_vote == vote.value
    end)
  end

  test "votes from different users are not lost", context do
    %{owner: owner, member: member, other: other, post: post, community: community} = context

    results =
      race([
        fn -> Communities.vote_post(owner, post, 1) end,
        fn -> Communities.vote_post(member, post, 1) end,
        fn -> Communities.vote_post(other, post, -1) end
      ])

    assert Enum.all?(results, &match?({:ok, %PostVote{}}, &1))

    unboxed(fn ->
      assert Repo.aggregate(from(v in PostVote, where: v.post_id == ^post.id), :count) == 3
      assert {:ok, %{score: 1, my_vote: 1}} = Communities.get_post(member, community, post.id)
    end)
  end

  test "competing comment votes from one user do not create duplicate rows", context do
    %{member: member, post: post, comment: comment} = context

    results =
      race([
        fn -> Communities.vote_comment(member, comment, 1) end,
        fn -> Communities.vote_comment(member, comment, -1) end
      ])

    assert Enum.all?(results, &match?({:ok, %CommentVote{}}, &1))

    unboxed(fn ->
      assert [vote] = Repo.all(from v in CommentVote, where: v.comment_id == ^comment.id)
      assert vote.value in [-1, 1]
      assert [%{score: score, my_vote: my_vote}] = Communities.list_comments(member, post)
      assert score == vote.value
      assert my_vote == vote.value
    end)
  end

  test "clearing a vote while another request changes it leaves a consistent score", context do
    %{member: member, post: post, community: community} = context
    unboxed(fn -> {:ok, _} = Communities.vote_post(member, post, 1) end)

    results =
      race([
        fn -> Communities.vote_post(member, post, 0) end,
        fn -> Communities.vote_post(member, post, -1) end
      ])

    assert Enum.all?(results, &match?({:ok, _}, &1))

    unboxed(fn ->
      votes = Repo.all(from v in PostVote, where: v.post_id == ^post.id)
      assert length(votes) <= 1
      score = Enum.sum(Enum.map(votes, & &1.value))
      assert score in [0, -1]
      assert {:ok, current} = Communities.get_post(member, community, post.id)
      assert current.score == score
      assert current.my_vote == score
    end)
  end
end
