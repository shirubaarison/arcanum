defmodule ArcanumWeb.RealtimePostsTest do
  use ArcanumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Arcanum.AccountsFixtures
  alias Arcanum.Communities

  setup do
    owner = user_scope_fixture()
    member = user_scope_fixture()
    {:ok, community} = Communities.create_community(owner, %{name: "Private"})
    {:ok, membership} = Communities.add_member(owner, community, member.user)
    %{owner: owner, member: member, community: community, membership: membership}
  end

  test "new posts and changing votes update a second user's open feed", context do
    %{owner: owner, member: member, community: community} = context
    conn = log_in_user(build_conn(), member.user)
    {:ok, viewer, _} = live(conn, ~p"/communities/#{community}")
    {:ok, post} = Communities.create_post(owner, community, %{title: "Live post", body: "Text"})
    _ = :sys.get_state(viewer.pid)
    assert has_element?(viewer, "#posts-#{post.id}", "Live post")

    {:ok, _} = Communities.vote_post(owner, post, 1)
    _ = :sys.get_state(viewer.pid)
    assert has_element?(viewer, "#post-score-#{post.id}", "1")
    # The viewer sees the total, not the other user's selected vote.
    assert has_element?(viewer, "#upvote-post-#{post.id}[aria-pressed=false]")
    {:ok, _} = Communities.vote_post(owner, post, -1)
    _ = :sys.get_state(viewer.pid)
    assert has_element?(viewer, "#post-score-#{post.id}", "-1")
    {:ok, _} = Communities.vote_post(owner, post, 0)
    _ = :sys.get_state(viewer.pid)
    assert has_element?(viewer, "#post-score-#{post.id}", "0")
  end

  test "comments, replies and scores update without losing the viewer's draft", context do
    %{owner: owner, member: member, community: community} = context
    {:ok, post} = Communities.create_post(owner, community, %{title: "Discussion", body: "Text"})

    {:ok, viewer, _} =
      live(log_in_user(build_conn(), member.user), ~p"/communities/#{community}/posts/#{post}")

    viewer |> form("#comment-form", comment: %{body: "Unsent draft"}) |> render_change()

    {:ok, comment} = Communities.create_comment(owner, post, %{body: "Live comment"})
    _ = :sys.get_state(viewer.pid)
    assert has_element?(viewer, "#comments-#{comment.id}", "Live comment")
    assert has_element?(viewer, "#comment-form textarea", "Unsent draft")
    {:ok, reply} = Communities.create_comment(owner, post, %{body: "Live reply"}, comment.id)
    _ = :sys.get_state(viewer.pid)
    assert has_element?(viewer, "#comments-#{reply.id}", "Live reply")

    {:ok, _} = Communities.vote_comment(owner, comment, 1)
    {:ok, _} = Communities.vote_post(owner, post, -1)
    _ = :sys.get_state(viewer.pid)
    assert has_element?(viewer, "#comment-score-#{comment.id}", "1 points")
    assert has_element?(viewer, "#post-score", "-1 points")
    assert has_element?(viewer, "#upvote-comment-#{comment.id}[aria-pressed=false]")
    assert has_element?(viewer, "#comment-form textarea", "Unsent draft")
  end

  test "live updates preserve a new-post draft", context do
    %{owner: owner, member: member, community: community} = context

    {:ok, viewer, _} =
      live(log_in_user(build_conn(), member.user), ~p"/communities/#{community}/posts/new")

    viewer
    |> form("#post-form", post: %{title: "Draft title", body: "Draft body"})
    |> render_change()

    {:ok, _} = Communities.create_post(owner, community, %{title: "Other post", body: "Text"})
    _ = :sys.get_state(viewer.pid)
    assert has_element?(viewer, "#post-form input[value='Draft title']")
    assert has_element?(viewer, "#post-form textarea", "Draft body")
  end

  test "removed members lose access to both open feeds and post pages", context do
    %{owner: owner, member: member, community: community, membership: membership} = context
    {:ok, post} = Communities.create_post(owner, community, %{title: "Private", body: "Text"})
    conn = log_in_user(build_conn(), member.user)
    {:ok, feed, _} = live(conn, ~p"/communities/#{community}")
    {:ok, detail, _} = live(conn, ~p"/communities/#{community}/posts/#{post}")
    feed_ref = Process.monitor(feed.pid)
    detail_ref = Process.monitor(detail.pid)
    {:ok, _} = Communities.remove_member(owner, membership)
    assert_receive {:DOWN, ^feed_ref, :process, _, _}, 1000
    assert_receive {:DOWN, ^detail_ref, :process, _, _}, 1000
    assert_redirect(feed, ~p"/communities")
    assert_redirect(detail, ~p"/communities")
  end

  test "deleting a community redirects active viewers", context do
    %{owner: owner, member: member, community: community} = context
    {:ok, viewer, _} = live(log_in_user(build_conn(), member.user), ~p"/communities/#{community}")
    ref = Process.monitor(viewer.pid)
    {:ok, _} = Communities.delete_community(owner, community)
    assert_receive {:DOWN, ^ref, :process, _, _}, 1000
    assert_redirect(viewer, ~p"/communities")
  end

  test "updates from other communities are not displayed", context do
    %{owner: owner, member: member, community: community} = context
    {:ok, viewer, _} = live(log_in_user(build_conn(), member.user), ~p"/communities/#{community}")
    {:ok, other} = Communities.create_community(owner, %{name: "Other"})
    {:ok, post} = Communities.create_post(owner, other, %{title: "Secret", body: "Text"})
    send(viewer.pid, {:community_changed, other.id})
    _ = :sys.get_state(viewer.pid)
    refute has_element?(viewer, "#posts-#{post.id}")
  end
end
