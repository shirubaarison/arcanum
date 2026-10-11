defmodule Arcanum.Communities.MissingRecordsTest do
  use Arcanum.DataCase, async: true

  import Arcanum.AccountsFixtures

  alias Arcanum.Communities
  alias Arcanum.Communities.{Comment, Community, Post}

  setup do
    scope = user_scope_fixture()
    {:ok, community} = Communities.create_community(scope, %{name: "Private"})
    {:ok, post} = Communities.create_post(scope, community, %{title: "Hello", body: "Text"})
    %{scope: scope, community: community, post: post}
  end

  test "community lookup handles missing, malformed, private and deleted records", context do
    %{scope: scope, community: community} = context
    assert {:ok, ^community} = Communities.get_community(scope, community.id)

    for id <- [nil, "not-an-id", "1.5", -1, "999999999", %{}] do
      assert {:error, :not_found} = Communities.get_community(scope, id)
    end

    assert {:error, :not_found} = Communities.get_community(user_scope_fixture(), community.id)
    {:ok, _} = Communities.delete_community(scope, community)
    assert {:error, :not_found} = Communities.get_community(scope, community.id)
    assert {:error, :not_found} = Communities.change_community(scope, community)
    assert {:error, :not_found} = Communities.change_post(scope, community)
  end

  test "post lookups are scoped and handle malformed IDs", context do
    %{scope: scope, community: community, post: post} = context
    assert {:ok, %{id: id}} = Communities.get_post(scope, community, post.id)
    assert id == post.id

    for id <- [nil, "bad", -1, "999999999"] do
      assert {:error, :not_found} = Communities.get_post(scope, community, id)
    end

    {:ok, other} = Communities.create_community(scope, %{name: "Other"})
    assert {:error, :not_found} = Communities.get_post(scope, other, post.id)
    assert {:error, :not_found} = Communities.get_post(user_scope_fixture(), community, post.id)
    assert {:error, :not_found} = Communities.get_post(scope, %Community{id: -1}, post.id)
  end

  test "stale post and comment structs return errors instead of raising", context do
    %{scope: scope, post: post} = context
    {:ok, comment} = Communities.create_comment(scope, post, %{body: "Comment"})
    Repo.delete!(comment)
    assert {:error, :not_found} = Communities.vote_comment(scope, comment, 1)
    assert {:error, :not_found} = Communities.vote_comment(scope, %Comment{id: -1}, 1)

    Repo.delete!(post)
    assert {:error, :not_found} = Communities.create_comment(scope, post, %{body: "Reply"})
    assert {:error, :not_found} = Communities.vote_post(scope, post, 1)
    assert {:error, :not_found} = Communities.change_comment(scope, post)
    assert {:error, :not_found} = Communities.list_comments(scope, post)
    assert {:error, :not_found} = Communities.vote_post(scope, %Post{id: -1}, 1)
  end
end
