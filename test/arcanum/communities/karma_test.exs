defmodule Arcanum.Communities.KarmaTest do
  use Arcanum.DataCase, async: true

  import Arcanum.AccountsFixtures

  alias Arcanum.Communities

  setup do
    author = user_scope_fixture()
    viewer = user_scope_fixture()
    {:ok, community} = Communities.create_community(author, %{name: "Shared"})
    {:ok, membership} = Communities.add_member(author, community, viewer.user)
    {:ok, post} = Communities.create_post(author, community, %{title: "Post", body: "Text"})
    %{author: author, viewer: viewer, community: community, membership: membership, post: post}
  end

  test "karma sums received votes on posts and comments, including comments on others' posts",
       context do
    %{author: author, viewer: viewer, community: community, post: post} = context

    {:ok, other_post} =
      Communities.create_post(viewer, community, %{title: "Other", body: "Text"})

    {:ok, comment} = Communities.create_comment(author, other_post, %{body: "Comment"})
    {:ok, other_comment} = Communities.create_comment(viewer, post, %{body: "Other comment"})
    {:ok, _} = Communities.vote_post(viewer, post, 1)
    {:ok, _} = Communities.vote_comment(viewer, comment, 1)
    {:ok, _} = Communities.vote_post(author, other_post, 1)
    {:ok, _} = Communities.vote_comment(author, other_comment, 1)

    assert Communities.user_karma(viewer, author.user) == 2
    assert Communities.user_karma(author, author.user) == 2
  end

  test "karma starts at zero, can be negative, and tracks changed and cleared votes", context do
    %{author: author, viewer: viewer, post: post} = context
    assert Communities.user_karma(viewer, author.user) == 0
    {:ok, _} = Communities.vote_post(viewer, post, -1)
    assert Communities.user_karma(viewer, author.user) == -1
    {:ok, _} = Communities.vote_post(viewer, post, 1)
    assert Communities.user_karma(viewer, author.user) == 1
    {:ok, _} = Communities.vote_post(viewer, post, 0)
    assert Communities.user_karma(viewer, author.user) == 0
  end

  test "private-community votes are excluded for other viewers", context do
    %{author: author, viewer: viewer, post: post} = context
    {:ok, private} = Communities.create_community(author, %{name: "Private"})

    {:ok, hidden_post} =
      Communities.create_post(author, private, %{title: "Hidden", body: "Text"})

    {:ok, hidden_comment} = Communities.create_comment(author, hidden_post, %{body: "Hidden"})
    {:ok, _} = Communities.vote_post(author, hidden_post, 1)
    {:ok, _} = Communities.vote_comment(author, hidden_comment, 1)
    {:ok, _} = Communities.vote_post(viewer, post, 1)

    assert Communities.user_karma(viewer, author.user) == 1
    assert Communities.user_karma(author, author.user) == 3
    assert Communities.user_karma(user_scope_fixture(), author.user) == 0
  end

  test "deleted communities and lost memberships remove their karma", context do
    %{author: author, viewer: viewer, community: community, membership: membership, post: post} =
      context

    {:ok, _} = Communities.vote_post(viewer, post, 1)
    {:ok, _} = Communities.remove_member(author, membership)
    assert Communities.user_karma(viewer, author.user) == 0
    assert Communities.user_karma(author, author.user) == 1
    {:ok, _} = Communities.delete_community(author, community)
    assert Communities.user_karma(author, author.user) == 0
  end
end
