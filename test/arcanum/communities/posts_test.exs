defmodule Arcanum.Communities.PostsTest do
  use Arcanum.DataCase, async: true

  import Arcanum.AccountsFixtures

  alias Arcanum.Communities
  alias Arcanum.Communities.{Comment, CommentVote, Post, PostVote}

  setup do
    scope = user_scope_fixture()
    outsider = user_scope_fixture()
    {:ok, community} = Communities.create_community(scope, %{name: "Elixir"})
    {:ok, post} = Communities.create_post(scope, community, %{title: "Hello", body: "First post"})
    %{scope: scope, outsider: outsider, community: community, post: post}
  end

  test "creates posts with trusted author and community IDs", context do
    %{scope: scope, outsider: outsider, community: community} = context

    assert {:ok, post} =
             Communities.create_post(scope, community, %{
               title: "Another",
               body: "Text",
               author_id: outsider.user.id,
               community_id: -1
             })

    assert post.author_id == scope.user.id
    assert post.community_id == community.id
    assert %DateTime{} = post.inserted_at
    assert [latest, _] = Communities.list_posts(scope, community)
    assert latest.id == post.id
    assert Ecto.assoc_loaded?(latest.author)
    assert latest.score == 0
    assert latest.my_vote == 0
  end

  test "validates post title and body", %{scope: scope, community: community} do
    assert {:error, changeset} =
             Communities.create_post(scope, community, %{title: "", body: " "})

    assert %{title: ["can't be blank"], body: ["can't be blank"]} = errors_on(changeset)

    assert {:error, changeset} =
             Communities.create_post(scope, community, %{
               title: String.duplicate("a", 256),
               body: String.duplicate("a", 50_001)
             })

    assert Map.has_key?(errors_on(changeset), :title)
    assert Map.has_key?(errors_on(changeset), :body)
  end

  test "outsiders cannot read, post, comment or vote", context do
    %{outsider: outsider, community: community, post: post, scope: scope} = context
    {:ok, comment} = Communities.create_comment(scope, post, %{body: "Comment"})
    assert {:error, :not_found} = Communities.list_posts(outsider, community)

    assert_raise Ecto.NoResultsError, fn ->
      Communities.get_post!(outsider, community, post.id)
    end

    assert {:error, :not_found} = Communities.list_comments(outsider, post)

    assert {:error, :unauthorized} =
             Communities.create_post(outsider, community, %{title: "No", body: "No"})

    assert {:error, :unauthorized} = Communities.create_comment(outsider, post, %{body: "No"})
    assert {:error, :unauthorized} = Communities.vote_post(outsider, post, 1)
    assert {:error, :unauthorized} = Communities.vote_comment(outsider, comment, 1)
  end

  test "post queries do not leak other communities", %{
    scope: scope,
    community: community,
    post: post
  } do
    {:ok, other} = Communities.create_community(scope, %{name: "Other"})
    {:ok, hidden} = Communities.create_post(scope, other, %{title: "Other post", body: "Text"})
    assert Enum.map(Communities.list_posts(scope, community), & &1.id) == [post.id]
    assert_raise Ecto.NoResultsError, fn -> Communities.get_post!(scope, community, hidden.id) end
  end

  test "members can participate and removed members cannot", context do
    %{scope: owner, outsider: member, community: community, post: post} = context
    {:ok, membership} = Communities.add_member(owner, community, member.user)

    assert {:ok, _} =
             Communities.create_post(member, community, %{title: "Member post", body: "Text"})

    assert {:ok, _} = Communities.create_comment(member, post, %{body: "Member comment"})
    assert {:ok, _} = Communities.vote_post(member, post, 1)
    {:ok, _} = Communities.remove_member(owner, membership)
    assert {:error, :unauthorized} = Communities.vote_post(member, post, 0)
    assert {:error, :unauthorized} = Communities.create_comment(member, post, %{body: "No"})
  end

  test "post votes are unique, changeable and clearable", context do
    %{scope: scope, outsider: member, community: community, post: post} = context
    {:ok, _} = Communities.add_member(scope, community, member.user)
    assert {:ok, _} = Communities.vote_post(scope, post, 1)
    assert {:ok, _} = Communities.vote_post(scope, post, 1)
    assert Repo.aggregate(PostVote, :count) == 1
    assert {:ok, _} = Communities.vote_post(member, post, 1)
    assert Communities.get_post!(scope, community, post.id).score == 2
    assert {:ok, _} = Communities.vote_post(scope, post, -1)
    voted = Communities.get_post!(scope, community, post.id)
    assert voted.score == 0
    assert voted.my_vote == -1
    assert {:ok, :cleared} = Communities.vote_post(scope, post, 0)
    voted = Communities.get_post!(scope, community, post.id)
    assert voted.score == 1
    assert voted.my_vote == 0
    assert Repo.aggregate(PostVote, :count) == 1
    assert {:error, changeset} = Communities.vote_post(scope, post, 2)
    assert %{value: ["is invalid"]} = errors_on(changeset)
  end

  test "comments and replies are ordered into threads", %{scope: scope, post: post} do
    {:ok, root} = Communities.create_comment(scope, post, %{body: "Root", author_id: -1})
    {:ok, other} = Communities.create_comment(scope, post, %{body: "Other"})
    {:ok, reply} = Communities.create_comment(scope, post, %{body: "Reply"}, root.id)
    {:ok, nested} = Communities.create_comment(scope, post, %{body: "Nested"}, reply.id)
    comments = Communities.list_comments(scope, post)
    assert Enum.map(comments, & &1.id) == [root.id, reply.id, nested.id, other.id]
    assert Enum.map(comments, & &1.depth) == [0, 1, 2, 0]
    assert root.author_id == scope.user.id
    assert Enum.all?(comments, &Ecto.assoc_loaded?(&1.author))
    assert {:error, changeset} = Communities.create_comment(scope, post, %{body: " "})
    assert %{body: ["can't be blank"]} = errors_on(changeset)
  end

  test "replies cannot target another post, including at the database level", context do
    %{scope: scope, community: community, post: post} = context
    {:ok, other} = Communities.create_post(scope, community, %{title: "Other", body: "Text"})
    {:ok, parent} = Communities.create_comment(scope, other, %{body: "Parent"})

    assert {:error, :unauthorized} =
             Communities.create_comment(scope, post, %{body: "Reply"}, parent.id)

    assert {:error, changeset} =
             %Comment{post_id: post.id, author_id: scope.user.id, parent_id: parent.id}
             |> Comment.changeset(%{body: "Invalid"})
             |> Repo.insert()

    assert %{parent_id: ["does not exist"]} = errors_on(changeset)
  end

  test "comment votes are unique, changeable and clearable", %{scope: scope, post: post} do
    {:ok, comment} = Communities.create_comment(scope, post, %{body: "Comment"})
    assert {:ok, _} = Communities.vote_comment(scope, comment, 1)
    assert {:ok, _} = Communities.vote_comment(scope, comment, 1)
    assert Repo.aggregate(CommentVote, :count) == 1
    assert [%{score: 1, my_vote: 1}] = Communities.list_comments(scope, post)
    assert {:ok, _} = Communities.vote_comment(scope, comment, -1)
    assert [%{score: -1, my_vote: -1}] = Communities.list_comments(scope, post)
    assert {:ok, :cleared} = Communities.vote_comment(scope, comment, 0)
    assert [%{score: 0, my_vote: 0}] = Communities.list_comments(scope, post)
    assert Repo.aggregate(CommentVote, :count) == 0
    assert {:error, changeset} = Communities.vote_comment(scope, comment, 2)
    refute changeset.valid?
  end

  test "deleted communities hide posts and reject participation", context do
    %{scope: scope, community: community, post: post} = context
    {:ok, comment} = Communities.create_comment(scope, post, %{body: "Comment"})
    {:ok, _} = Communities.delete_community(scope, community)
    assert {:error, :not_found} = Communities.list_posts(scope, community)

    assert {:error, :unauthorized} =
             Communities.create_post(scope, community, %{title: "No", body: "No"})

    assert {:error, :unauthorized} = Communities.create_comment(scope, post, %{body: "No"})
    assert {:error, :unauthorized} = Communities.vote_post(scope, post, 1)
    assert {:error, :unauthorized} = Communities.vote_comment(scope, comment, 1)
    assert Repo.get!(Post, post.id)
  end
end
