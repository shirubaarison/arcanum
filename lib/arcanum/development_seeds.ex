defmodule Arcanum.DevelopmentSeeds do
  @moduledoc "Repeatable demo data for local development, preserving existing matching records."

  import Ecto.Query

  alias Arcanum.Accounts.{Scope, User}
  alias Arcanum.Communities
  alias Arcanum.Communities.{Comment, CommentVote, Community, CommunityMembership, Post, PostVote}
  alias Arcanum.Repo

  @password "arcanum-demo-password"

  def run do
    if not Code.ensure_loaded?(Mix) or Mix.env() not in [:dev, :test] do
      raise "Demo seeds are only available in development and tests"
    end

    {:ok, data} = Repo.transaction(&seed/0)
    data
  end

  defp seed do
    users = Map.new(~w(alice bob carol dave), fn name -> {name, user(name)} end)
    alice = Scope.for_user(users["alice"])
    bob = Scope.for_user(users["bob"])
    carol = Scope.for_user(users["carol"])
    dave = Scope.for_user(users["dave"])

    commons =
      community(
        alice,
        "Demo Commons",
        "A private place to share ideas and meet the demo members."
      )

    elixir =
      community(
        bob,
        "Demo Elixir",
        "Small experiments, Phoenix tips, and things we are building."
      )

    books = community(carol, "Demo Book Club", "A separate private community for Carol and Dave.")

    member(alice, commons, users["bob"], :admin)
    member(alice, commons, users["carol"], :member)
    member(bob, elixir, users["alice"], :member)
    member(carol, books, users["dave"], :member)

    welcome =
      post(
        alice,
        commons,
        "Welcome to the commons",
        "Introduce yourself below. What have you been working on lately?"
      )

    ideas =
      post(
        bob,
        commons,
        "What makes a good small community?",
        "I like thoughtful conversations over busy feeds. What would you like to see here?"
      )

    phoenix =
      post(
        bob,
        elixir,
        "Building with Phoenix LiveView",
        "Try opening this community in two browser sessions. Posts, replies, and votes update live."
      )

    project =
      post(
        alice,
        elixir,
        "A weekend Elixir project",
        "I am experimenting with a tiny reading-list app. Share a project you would like to build."
      )

    reading =
      post(
        carol,
        books,
        "What are we reading this month?",
        "This conversation is only visible to members of Demo Book Club."
      )

    notes =
      post(
        dave,
        books,
        "Keeping a reading journal",
        "A few notes after each chapter help me remember the ideas worth discussing."
      )

    introduction =
      comment(carol, welcome, "Hello! I am here for good conversations and book recommendations.")

    reply =
      comment(
        alice,
        welcome,
        "Welcome, Carol. What book would you recommend first?",
        introduction.id
      )

    nested = comment(bob, welcome, "I would also love a recommendation.", reply.id)

    idea =
      comment(alice, ideas, "Clear expectations and a little room for curiosity go a long way.")

    tip =
      comment(alice, phoenix, "Streams make a great starting point for a live discussion feed.")

    followup =
      comment(bob, phoenix, "Agreed. Keep authorization checks in the context too.", tip.id)

    book =
      comment(dave, reading, "I would like to pick something we can discuss chapter by chapter.")

    book_reply = comment(carol, reading, "Good idea. Let's choose together.", book.id)

    post_vote(bob, welcome, 1)
    post_vote(carol, welcome, 1)
    post_vote(alice, ideas, -1)
    post_vote(alice, phoenix, 1)
    post_vote(bob, project, 1)
    post_vote(dave, reading, 1)
    post_vote(carol, notes, 1)
    comment_vote(alice, introduction, 1)
    comment_vote(carol, reply, 1)
    comment_vote(alice, nested, 1)
    comment_vote(bob, idea, 1)
    comment_vote(bob, tip, 1)
    comment_vote(alice, followup, 1)
    comment_vote(carol, book, 1)
    comment_vote(dave, book_reply, 1)

    %{users: users, communities: [commons, elixir, books]}
  end

  defp user(name) do
    username = "demo_#{name}"
    email = "#{username}@example.com"

    case {Repo.get_by(User, email: email), Repo.get_by(User, username: username)} do
      {nil, nil} ->
        %User{}
        |> User.registration_changeset(%{email: email, username: username})
        |> User.password_changeset(%{password: @password})
        |> User.confirm_changeset()
        |> Repo.insert!()

      {%User{id: id} = user, %User{id: id}} ->
        user

      _ ->
        raise "Demo account #{username} conflicts with an existing account; no accounts were overwritten"
    end
  end

  defp community(scope, name, description) do
    case Repo.one(from c in Community, where: fragment("lower(?) = lower(?)", c.name, ^name)) do
      nil ->
        {:ok, community} =
          Communities.create_community(scope, %{name: name, description: description})

        community

      community ->
        owner =
          Repo.get_by(CommunityMembership,
            community_id: community.id,
            user_id: scope.user.id,
            role: :owner
          )

        if is_nil(owner) or not is_nil(community.deleted_at) do
          raise "Demo community #{name} is deleted or has a different owner; it was not modified"
        end

        community
    end
  end

  defp member(scope, community, user, role) do
    case Repo.get_by(CommunityMembership, community_id: community.id, user_id: user.id) do
      nil ->
        {:ok, membership} = Communities.add_member(scope, community, user, %{role: role})
        membership

      membership ->
        membership
    end
  end

  defp post(scope, community, title, body) do
    case Repo.get_by(Post, community_id: community.id, author_id: scope.user.id, title: title) do
      nil ->
        {:ok, post} = Communities.create_post(scope, community, %{title: title, body: body})
        post

      post ->
        post
    end
  end

  defp comment(scope, post, body, parent_id \\ nil) do
    query =
      from c in Comment,
        where: c.post_id == ^post.id and c.author_id == ^scope.user.id and c.body == ^body

    query =
      if parent_id,
        do: where(query, [c], c.parent_id == ^parent_id),
        else: where(query, [c], is_nil(c.parent_id))

    case Repo.one(query) do
      nil ->
        {:ok, comment} = Communities.create_comment(scope, post, %{body: body}, parent_id)
        comment

      comment ->
        comment
    end
  end

  defp post_vote(scope, post, value) do
    unless Repo.get_by(PostVote, post_id: post.id, user_id: scope.user.id) do
      {:ok, _} = Communities.vote_post(scope, post, value)
    end
  end

  defp comment_vote(scope, comment, value) do
    unless Repo.get_by(CommentVote, comment_id: comment.id, user_id: scope.user.id) do
      {:ok, _} = Communities.vote_comment(scope, comment, value)
    end
  end
end
