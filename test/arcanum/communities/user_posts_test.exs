defmodule Arcanum.Communities.UserPostsTest do
  use Arcanum.DataCase, async: true

  import Arcanum.AccountsFixtures

  alias Arcanum.Accounts
  alias Arcanum.Communities

  setup do
    author = user_scope_fixture()
    viewer = user_scope_fixture()
    {:ok, shared} = Communities.create_community(author, %{name: "Shared"})
    {:ok, membership} = Communities.add_member(author, shared, viewer.user)
    {:ok, visible} = Communities.create_post(author, shared, %{title: "Visible", body: "Text"})
    {:ok, private} = Communities.create_community(author, %{name: "Private"})
    {:ok, hidden} = Communities.create_post(author, private, %{title: "Hidden", body: "Text"})

    %{
      author: author,
      viewer: viewer,
      shared: shared,
      private: private,
      visible: visible,
      hidden: hidden,
      membership: membership
    }
  end

  test "another user sees only the profile author's posts in shared communities", context do
    %{author: author, viewer: viewer, shared: shared, visible: visible} = context
    {:ok, _} = Communities.create_post(viewer, shared, %{title: "Someone else", body: "Text"})
    {:ok, _} = Communities.vote_post(viewer, visible, 1)

    assert [post] = Communities.list_user_posts(viewer, author.user)
    assert post.id == visible.id
    assert post.score == 1
    assert post.my_vote == 1
    assert post.community.id == shared.id
    assert post.author.id == author.user.id
    assert Communities.list_shared_communities(viewer, author.user) == [shared]
  end

  test "own profile includes all own posts in active memberships", context do
    %{author: author, visible: visible, hidden: hidden, private: private} = context

    assert Enum.map(Communities.list_user_posts(author, author.user), & &1.id) ==
             [hidden.id, visible.id]

    {:ok, _} = Communities.delete_community(author, private)
    assert Enum.map(Communities.list_user_posts(author, author.user), & &1.id) == [visible.id]
  end

  test "removing the viewer immediately removes visibility", context do
    %{author: author, viewer: viewer, shared: shared, membership: membership} = context
    {:ok, _} = Communities.remove_member(author, membership)
    assert Communities.list_user_posts(viewer, author.user) == []
    assert Communities.list_shared_communities(viewer, author.user) == []

    {:ok, _} = Communities.add_member(author, shared, viewer.user)
    {:ok, _} = Communities.delete_community(author, shared)
    assert Communities.list_user_posts(viewer, author.user) == []
  end

  test "author must still belong to a community, even if the viewer can read its posts",
       context do
    %{author: author, viewer: viewer} = context
    {:ok, community} = Communities.create_community(viewer, %{name: "Viewer's community"})
    {:ok, membership} = Communities.add_member(viewer, community, author.user)
    {:ok, post} = Communities.create_post(author, community, %{title: "Old post", body: "Text"})
    {:ok, _} = Communities.remove_member(viewer, membership)

    refute Enum.any?(Communities.list_user_posts(viewer, author.user), &(&1.id == post.id))
    refute Enum.any?(Communities.list_user_posts(author, author.user), &(&1.id == post.id))
  end

  test "no shared communities means no posts", %{author: author} do
    outsider = user_scope_fixture()
    assert Communities.list_user_posts(outsider, author.user) == []
    assert Communities.list_shared_communities(outsider, author.user) == []
  end

  test "profile lookup returns only safe fields and handles invalid IDs", context do
    %{author: author, viewer: viewer} = context
    assert {:ok, profile} = Accounts.get_user_profile(viewer, author.user.username)
    assert Map.keys(profile) |> Enum.sort() == [:id, :inserted_at, :username]
    assert profile.username == author.user.username

    for username <- ["missing", "not-a-username", "999999999"] do
      assert {:error, :not_found} = Accounts.get_user_profile(viewer, username)
    end
  end
end
