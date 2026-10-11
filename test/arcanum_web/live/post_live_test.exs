defmodule ArcanumWeb.PostLiveTest do
  use ArcanumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Arcanum.AccountsFixtures

  alias Arcanum.Communities

  setup %{conn: conn} do
    scope = user_scope_fixture()
    {:ok, community} = Communities.create_community(scope, %{name: "Elixir"})
    %{scope: scope, community: community, conn: log_in_user(conn, scope.user)}
  end

  test "community route shows only its posts, with settings on a separate page", context do
    %{conn: conn, scope: scope, community: community} = context
    {:ok, post} = Communities.create_post(scope, community, %{title: "Visible", body: "Text"})
    {:ok, other} = Communities.create_community(scope, %{name: "Other"})
    {:ok, hidden} = Communities.create_post(scope, other, %{title: "Hidden", body: "Text"})
    {:ok, view, _} = live(conn, ~p"/communities/#{community}")
    assert has_element?(view, "#posts-#{post.id}")
    refute has_element?(view, "#posts-#{hidden.id}")
    refute has_element?(view, "#community-form")
    assert has_element?(view, "#community-settings[href='/communities/#{community.id}/edit']")
    {:ok, edit, _} = live(conn, ~p"/communities/#{community}/edit")
    assert has_element?(edit, "#community-form")
    refute has_element?(edit, "#posts")
  end

  test "empty feed and post creation", %{conn: conn, scope: scope, community: community} do
    {:ok, feed, _} = live(conn, ~p"/communities/#{community}")
    assert has_element?(feed, "#posts-empty")
    {:ok, view, _} = live(conn, ~p"/communities/#{community}/posts/new")
    view |> form("#post-form", post: %{title: "", body: ""}) |> render_submit()
    assert Communities.list_posts(scope, community) == []
    view |> form("#post-form", post: %{title: "First", body: "Hello"}) |> render_submit()
    [post] = Communities.list_posts(scope, community)
    assert_redirect(view, ~p"/communities/#{community}/posts/#{post}")
    {:ok, next, _} = live(conn, ~p"/communities/#{community}/posts/new")
    assert has_element?(next, "#post-form input[name='post[title]']:not([value])")

    assert next
           |> element("#post-form textarea")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.text() == ""
  end

  test "a stale feed vote reports failure instead of crashing", context do
    %{conn: conn, scope: scope, community: community} = context
    {:ok, post} = Communities.create_post(scope, community, %{title: "Gone", body: "Text"})
    {:ok, view, _} = live(conn, ~p"/communities/#{community}")
    Arcanum.Repo.delete!(post)

    view |> element("#upvote-post-#{post.id}") |> render_click()
    assert has_element?(view, "#flash-error", "Could not save your vote.")
    assert has_element?(view, "#community-name")
  end

  test "refresh redirects when the displayed post no longer exists", context do
    %{conn: conn, scope: scope, community: community} = context
    {:ok, post} = Communities.create_post(scope, community, %{title: "Gone", body: "Text"})
    {:ok, view, _} = live(conn, ~p"/communities/#{community}/posts/#{post}")
    Arcanum.Repo.delete!(post)
    send(view.pid, {:community_changed, community.id})

    assert_redirect(view, ~p"/communities")
  end

  test "votes in the feed can change and clear", context do
    %{conn: conn, scope: scope, community: community} = context
    {:ok, post} = Communities.create_post(scope, community, %{title: "Vote", body: "Text"})
    {:ok, view, _} = live(conn, ~p"/communities/#{community}")
    view |> element("#upvote-post-#{post.id}") |> render_click()
    assert has_element?(view, "#post-score-#{post.id}", "1")
    assert has_element?(view, "#upvote-post-#{post.id}[aria-pressed=true]")
    view |> element("#downvote-post-#{post.id}") |> render_click()
    assert has_element?(view, "#post-score-#{post.id}", "-1")
    view |> element("#downvote-post-#{post.id}") |> render_click()
    assert has_element?(view, "#post-score-#{post.id}", "0")
  end

  test "browser button values cannot overwrite post or comment votes", context do
    %{conn: conn, scope: scope, community: community} = context
    {:ok, post} = Communities.create_post(scope, community, %{title: "Vote", body: "Text"})
    {:ok, comment} = Communities.create_comment(scope, post, %{body: "Comment"})

    {:ok, feed, _} = live(conn, ~p"/communities/#{community}")
    assert has_element?(feed, "#upvote-post-#{post.id}[phx-value-vote='1']")
    feed |> element("#upvote-post-#{post.id}") |> render_click(%{"value" => ""})
    assert has_element?(feed, "#post-score-#{post.id}", "1")
    feed |> element("#downvote-post-#{post.id}") |> render_click(%{"value" => ""})
    assert has_element?(feed, "#post-score-#{post.id}", "-1")
    feed |> element("#downvote-post-#{post.id}") |> render_click(%{"value" => ""})
    assert has_element?(feed, "#post-score-#{post.id}", "0")

    {:ok, view, _} = live(conn, ~p"/communities/#{community}/posts/#{post}")
    view |> element("#upvote-post") |> render_click(%{"value" => ""})
    assert has_element?(view, "#post-score", "1 points")
    view |> element("#upvote-comment-#{comment.id}") |> render_click(%{"value" => ""})
    assert has_element?(view, "#comment-score-#{comment.id}", "1 points")
    view |> element("#downvote-comment-#{comment.id}") |> render_click(%{"value" => ""})
    assert has_element?(view, "#comment-score-#{comment.id}", "-1 points")
    view |> element("#downvote-comment-#{comment.id}") |> render_click(%{"value" => ""})
    assert has_element?(view, "#comment-score-#{comment.id}", "0 points")
  end

  test "comments, replies and post/comment voting", context do
    %{conn: conn, scope: scope, community: community} = context
    {:ok, post} = Communities.create_post(scope, community, %{title: "Discuss", body: "Text"})
    {:ok, view, _} = live(conn, ~p"/communities/#{community}/posts/#{post}")
    assert has_element?(view, "#post-title", "Discuss")
    assert has_element?(view, "#comments-empty")
    view |> element("#upvote-post") |> render_click()
    assert has_element?(view, "#post-score", "1 points")
    view |> element("#upvote-post") |> render_click()
    assert has_element?(view, "#post-score", "0 points")
    view |> form("#comment-form", comment: %{body: ""}) |> render_submit()
    assert Communities.list_comments(scope, post) == []
    view |> form("#comment-form", comment: %{body: "First comment"}) |> render_change()
    assert has_element?(view, "#comment-form textarea", "First comment")
    view |> form("#comment-form", comment: %{body: "First comment"}) |> render_submit()

    assert view
           |> element("#comment-form textarea")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.text() == ""

    [comment] = Communities.list_comments(scope, post)
    assert has_element?(view, "#comments-#{comment.id}")
    view |> element("#upvote-comment-#{comment.id}") |> render_click()
    assert has_element?(view, "#comment-score-#{comment.id}", "1 points")
    view |> element("#downvote-comment-#{comment.id}") |> render_click()
    assert has_element?(view, "#comment-score-#{comment.id}", "-1 points")
    view |> element("#downvote-comment-#{comment.id}") |> render_click()
    assert has_element?(view, "#comment-score-#{comment.id}", "0 points")
    view |> element("#reply-#{comment.id}") |> render_click()
    assert has_element?(view, "#reply-target")
    view |> form("#comment-form", comment: %{body: "A reply"}) |> render_change()
    view |> form("#comment-form", comment: %{body: "A reply"}) |> render_submit()

    assert view
           |> element("#comment-form textarea")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.text() == ""

    [_, reply] = Communities.list_comments(scope, post)
    assert reply.parent_id == comment.id
    assert has_element?(view, "#comments-#{reply.id}")
    refute has_element?(view, "#reply-target")
    view |> element("#reply-#{reply.id}") |> render_click()
    view |> element("#cancel-reply") |> render_click()
    refute has_element?(view, "#reply-target")
  end

  test "post routes require login and community membership", context do
    %{conn: conn, community: community} = context

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(build_conn(), ~p"/communities/#{community}/posts/new")

    outsider = user_scope_fixture()
    {:ok, other} = Communities.create_community(outsider, %{name: "Private"})
    {:ok, post} = Communities.create_post(outsider, other, %{title: "Hidden", body: "Text"})

    assert {:error, {:live_redirect, %{to: "/communities"}}} =
             live(conn, ~p"/communities/#{other}/posts/#{post}")

    assert {:error, {:live_redirect, %{to: "/communities"}}} =
             live(conn, ~p"/communities/#{community}/posts/#{post}")
  end
end
