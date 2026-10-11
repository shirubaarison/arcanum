defmodule ArcanumWeb.UserProfileTest do
  use ArcanumWeb.ConnCase, async: true

  import Arcanum.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Arcanum.Communities

  setup %{conn: conn} do
    author = user_scope_fixture()
    viewer = user_scope_fixture()
    {:ok, shared} = Communities.create_community(author, %{name: "Shared"})
    {:ok, membership} = Communities.add_member(author, shared, viewer.user)
    {:ok, visible} = Communities.create_post(author, shared, %{title: "Visible", body: "Text"})
    {:ok, private} = Communities.create_community(author, %{name: "Private"})
    {:ok, hidden} = Communities.create_post(author, private, %{title: "Hidden", body: "Text"})

    %{
      conn: conn,
      author: author,
      viewer: viewer,
      shared: shared,
      visible: visible,
      hidden: hidden,
      membership: membership
    }
  end

  test "guests must log in", %{conn: conn, author: author} do
    conn = get(conn, ~p"/#{author.user.username}")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  test "another user's profile shows only mutual-community posts", context do
    %{conn: conn, author: author, viewer: viewer, visible: visible, hidden: hidden} = context
    {:ok, view, _} = live(log_in_user(conn, viewer.user), ~p"/#{author.user.username}")

    assert has_element?(view, "#profile-username", author.user.username)
    assert has_element?(view, "#profile-joined")
    assert has_element?(view, "#profile-karma", "0")
    assert has_element?(view, "#profile-post-#{visible.id}")
    assert has_element?(view, "#profile-post-time-#{visible.id}[phx-hook='LocalTime']")
    refute has_element?(view, "#profile-post-#{hidden.id}")
    assert has_element?(view, "#profile-post-count", "1")
    refute has_element?(view, "#profile-settings")
    refute has_element?(view, "#user-profile", author.user.email)
  end

  test "own profile includes all active-community posts and an account settings link", context do
    %{conn: conn, author: author, visible: visible, hidden: hidden} = context
    {:ok, view, _} = live(log_in_user(conn, author.user), ~p"/#{author.user.username}")

    assert has_element?(view, "#profile-post-#{visible.id}")
    assert has_element?(view, "#profile-post-#{hidden.id}")
    assert has_element?(view, "#profile-settings[href='/users/settings']")
    assert has_element?(view, "#my-profile[href='/#{author.user.username}']")
  end

  test "no mutual communities shows an empty state without revealing private posts", context do
    %{conn: conn, author: author, hidden: hidden, visible: visible} = context
    outsider = user_scope_fixture()
    {:ok, view, _} = live(log_in_user(conn, outsider.user), ~p"/#{author.user.username}")

    assert has_element?(view, "#profile-posts-empty")
    assert has_element?(view, "#profile-post-count", "0")
    refute has_element?(view, "#profile-post-#{visible.id}")
    refute has_element?(view, "#profile-post-#{hidden.id}")
  end

  test "missing and malformed profiles redirect cleanly", %{conn: conn, viewer: viewer} do
    conn = log_in_user(conn, viewer.user)

    for id <- ["999999999", "not-an-id"] do
      assert {:error, {:live_redirect, %{to: "/communities"}}} =
               live(conn, ~p"/#{id}")
    end
  end

  test "new shared posts and scores update in real time", context do
    %{conn: conn, author: author, viewer: viewer, shared: shared, visible: visible} = context
    {:ok, view, _} = live(log_in_user(conn, viewer.user), ~p"/#{author.user.username}")
    {:ok, post} = Communities.create_post(author, shared, %{title: "New", body: "Text"})
    assert has_element?(view, "#profile-post-#{post.id}")

    {:ok, _} = Communities.vote_post(viewer, visible, 1)
    assert has_element?(view, "#profile-post-score-#{visible.id}", "1 points")
    assert has_element?(view, "#profile-karma", "1")
  end

  test "live profile removes posts when the viewer loses membership", context do
    %{conn: conn, author: author, viewer: viewer, visible: visible, membership: membership} =
      context

    {:ok, view, _} = live(log_in_user(conn, viewer.user), ~p"/#{author.user.username}")
    {:ok, _} = Communities.vote_post(viewer, visible, 1)
    assert has_element?(view, "#profile-karma", "1")
    {:ok, _} = Communities.remove_member(author, membership)

    refute has_element?(view, "#profile-post-#{visible.id}")
    assert has_element?(view, "#profile-post-count", "0")
    assert has_element?(view, "#profile-karma", "0")
  end

  test "karma updates live for comment votes and cleared votes", context do
    %{conn: conn, author: author, viewer: viewer, visible: post} = context
    {:ok, comment} = Communities.create_comment(author, post, %{body: "Comment"})
    {:ok, view, _} = live(log_in_user(conn, viewer.user), ~p"/#{author.user.username}")
    assert has_element?(view, "#profile-karma", "0")

    {:ok, _} = Communities.vote_comment(viewer, comment, 1)
    assert has_element?(view, "#profile-karma", "1")
    {:ok, _} = Communities.vote_comment(viewer, comment, -1)
    assert has_element?(view, "#profile-karma", "-1")
    {:ok, _} = Communities.vote_comment(viewer, comment, 0)
    assert has_element?(view, "#profile-karma", "0")
  end

  test "own karma includes private votes while another user's view excludes them", context do
    %{conn: conn, author: author, viewer: viewer, hidden: hidden} = context
    {:ok, _} = Communities.vote_post(author, hidden, 1)
    {:ok, own, _} = live(log_in_user(conn, author.user), ~p"/#{author.user.username}")
    assert has_element?(own, "#profile-karma", "1")

    {:ok, other, _} = live(log_in_user(conn, viewer.user), ~p"/#{author.user.username}")
    assert has_element?(other, "#profile-karma", "0")
  end

  test "author names link to profiles from feeds, posts and comments", context do
    %{conn: conn, author: author, viewer: viewer, shared: shared, visible: post} = context
    conn = log_in_user(conn, viewer.user)
    {:ok, comment} = Communities.create_comment(author, post, %{body: "Comment"})
    href = "/#{author.user.username}"

    {:ok, feed, _} = live(conn, ~p"/communities/#{shared}")
    assert has_element?(feed, "#post-author-#{post.id}[href='#{href}']")

    {:ok, detail, _} = live(conn, ~p"/communities/#{shared}/posts/#{post}")
    assert has_element?(detail, "#post-author[href='#{href}']")
    assert has_element?(detail, "#comment-author-#{comment.id}[href='#{href}']")
  end

  test "live profile tracks changes to the author's shared memberships", context do
    %{conn: conn, author: author, viewer: viewer} = context
    {:ok, community} = Communities.create_community(viewer, %{name: "Viewer owned"})
    {:ok, membership} = Communities.add_member(viewer, community, author.user)

    {:ok, post} =
      Communities.create_post(author, community, %{title: "Shared post", body: "Text"})

    {:ok, view, _} = live(log_in_user(conn, viewer.user), ~p"/#{author.user.username}")

    assert has_element?(view, "#profile-post-#{post.id}")
    {:ok, _} = Communities.remove_member(viewer, membership)
    refute has_element?(view, "#profile-post-#{post.id}")
    {:ok, _} = Communities.add_member(viewer, community, author.user)
    assert has_element?(view, "#profile-post-#{post.id}")
  end
end
