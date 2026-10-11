defmodule Arcanum.Communities do
  @moduledoc """
  Community operations scoped to the authenticated caller.

  Members can read their communities. Owners and admins can edit communities
  and manage ordinary members. Only owners can assign admins or soft-delete
  communities. Owner transfer is not supported.

  Mutations return `{:error, :unauthorized}` for inaccessible communities.
  Non-bang lookups and read/form helpers return `{:error, :not_found}` for
  missing or inaccessible records. Bang lookups are explicitly opt-in.
  """

  import Ecto.Query

  alias Arcanum.Accounts.{Scope, User}
  alias Arcanum.Communities.{Comment, CommentVote, Community, CommunityMembership, Post, PostVote}
  alias Arcanum.Repo

  @doc "Subscribes the caller to ID-only notifications for an accessible community."
  def subscribe_community(scope, %Community{id: id}) do
    with {:ok, _community} <- get_community(scope, id) do
      Phoenix.PubSub.subscribe(Arcanum.PubSub, community_topic(id))
    end
  end

  def unsubscribe_community(%Scope{}, %Community{id: id}) do
    Phoenix.PubSub.unsubscribe(Arcanum.PubSub, community_topic(id))
  end

  defp community_topic(id), do: "community:#{id}"

  @doc "Lists the caller's active communities."
  def list_communities(%Scope{user: %User{id: user_id}}) do
    user_id |> accessible_communities() |> order_by([c], asc: c.id) |> Repo.all()
  end

  @doc "Gets an active community belonging to the caller, or raises Ecto.NoResultsError."
  def get_community!(%Scope{user: %User{id: user_id}}, id) do
    user_id |> accessible_communities() |> Repo.get!(id)
  end

  @doc "Gets an accessible community, returning :not_found without revealing private records."
  def get_community(%Scope{user: %User{id: user_id}}, id) do
    with {:ok, id} <- cast_id(id) do
      user_id |> accessible_communities() |> Repo.get(id) |> fetch_result()
    end
  end

  defp cast_id(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} when is_integer(id) and id > 0 -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end

  @doc "Gets an accessible community by its unique name, without exposing private communities."
  def get_community_by_name(%Scope{user: %User{id: user_id}}, name) when is_binary(name) do
    user_id
    |> accessible_communities()
    |> where([c], fragment("lower(?) = lower(?)", c.name, ^name))
    |> Repo.one()
    |> fetch_result()
  end

  defp fetch_result(nil), do: {:error, :not_found}
  defp fetch_result(record), do: {:ok, record}

  @doc "Creates a community and its owner membership atomically."
  def create_community(%Scope{user: %User{id: user_id}}, attrs) do
    transaction(fn ->
      community = %Community{} |> Community.changeset(attrs) |> persist(:insert)

      %CommunityMembership{community_id: community.id, user_id: user_id}
      |> CommunityMembership.changeset(%{role: :owner})
      |> persist(:insert)

      community
    end)
  end

  @doc "Returns an authorized changeset for a community form."
  def change_community(scope, %Community{id: id}, attrs \\ %{}) do
    with {:ok, community} <- get_community(scope, id) do
      membership = caller_membership(scope, id)

      if membership && membership.role in [:owner, :admin] do
        Community.changeset(community, attrs)
      else
        {:error, :unauthorized}
      end
    end
  end

  @doc "Updates a community as its owner or an admin."
  def update_community(scope, %Community{id: id}, attrs) do
    mutate(scope, id, fn community, caller ->
      authorize!(caller.role in [:owner, :admin])
      community |> Community.changeset(attrs) |> persist(:update)
    end)
  end

  @doc "Soft-deletes a community as its owner, preserving memberships."
  def delete_community(scope, %Community{id: id}) do
    mutate(scope, id, fn community, caller ->
      authorize!(caller.role == :owner)
      community |> Community.soft_delete_changeset() |> persist(:update)
    end)
  end

  @doc "Lists memberships with their users preloaded for an accessible community."
  def list_memberships(scope, %Community{id: id}) do
    with {:ok, _community} <- get_community(scope, id) do
      Repo.all(
        from m in CommunityMembership,
          where: m.community_id == ^id,
          order_by: [asc: m.id],
          preload: [:user]
      )
    end
  end

  @doc "Adds an existing user. Defaults to member; only owners can add admins."
  def add_member(scope, %Community{id: id}, %User{id: user_id}, attrs \\ %{}) do
    mutate(scope, id, fn _community, caller ->
      changeset =
        %CommunityMembership{community_id: id, user_id: user_id}
        |> CommunityMembership.changeset(attrs)

      authorize_role!(caller, Ecto.Changeset.get_field(changeset, :role))
      persist(changeset, :insert)
    end)
  end

  @doc "Lists up to 20 non-members by username for authorized owners and admins."
  def search_available_users(scope, %Community{id: id}, query \\ "") do
    mutate(
      scope,
      id,
      fn _community, caller ->
        authorize!(caller.role in [:owner, :admin])

        term = query |> String.trim() |> String.slice(0, 30)

        escaped =
          term
          |> String.replace("\\", "\\\\")
          |> String.replace("%", "\\%")
          |> String.replace("_", "\\_")

        pattern = "%" <> escaped <> "%"

        member_ids =
          from m in CommunityMembership, where: m.community_id == ^id, select: m.user_id

        Repo.all(
          from u in User,
            where: u.id not in subquery(member_ids) and ilike(u.username, ^pattern),
            order_by: [asc: u.username, asc: u.id],
            limit: 20,
            select: %{id: u.id, username: u.username}
        )
      end,
      false
    )
  end

  @doc "Adds an account selected by ID, checking permissions before looking up the user."
  def add_member_by_id(scope, %Community{id: id}, user_id) do
    mutate(scope, id, fn _community, caller ->
      authorize!(caller.role in [:owner, :admin])

      case Repo.get(User, user_id) do
        nil ->
          Repo.rollback(:user_not_found)

        user ->
          %CommunityMembership{community_id: id, user_id: user.id}
          |> CommunityMembership.changeset(%{})
          |> persist(:insert)
      end
    end)
  end

  @doc "Adds a registered user by email after checking the caller's permissions."
  def add_member_by_email(scope, %Community{id: id} = community, email) do
    mutate(scope, id, fn _community, caller ->
      authorize!(caller.role in [:owner, :admin])

      case Repo.get_by(User, email: String.trim(email)) do
        nil ->
          Repo.rollback(:user_not_found)

        user ->
          %CommunityMembership{community_id: community.id, user_id: user.id}
          |> CommunityMembership.changeset(%{})
          |> persist(:insert)
      end
    end)
  end

  @doc "Changes a non-owner's role. Only owners can manage admins."
  def update_membership(scope, %CommunityMembership{id: id, community_id: community_id}, attrs) do
    mutate(scope, community_id, fn _community, caller ->
      membership = get_membership!(community_id, id)
      authorize_role!(caller, membership.role)
      changeset = CommunityMembership.changeset(membership, attrs)
      authorize_role!(caller, Ecto.Changeset.get_field(changeset, :role))
      persist(changeset, :update)
    end)
  end

  @doc "Removes a non-owner. Only owners can remove admins."
  def remove_member(scope, %CommunityMembership{id: id, community_id: community_id}) do
    mutate(scope, community_id, fn _community, caller ->
      membership = get_membership!(community_id, id)
      authorize_role!(caller, membership.role)

      case Repo.delete(membership) do
        {:ok, membership} -> membership
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "Lists a community's posts, newest first, with authors and vote scores."
  def list_posts(%Scope{user: %User{id: user_id}} = scope, %Community{id: id}) do
    with {:ok, _community} <- get_community(scope, id) do
      Post
      |> scored(PostVote, :post_id, user_id)
      |> where([p], p.community_id == ^id)
      |> order_by([p], desc: p.inserted_at, desc: p.id)
      |> Repo.all()
    end
  end

  @doc "Lists active communities that both the viewer and profile user currently belong to."
  def list_shared_communities(%Scope{user: %User{id: viewer_id}}, %{id: profile_user_id}) do
    viewer_id
    |> shared_communities(profile_user_id)
    |> order_by([c], asc: c.id)
    |> Repo.all()
  end

  @doc "Lists a user's posts only in active communities shared with the authenticated viewer."
  def list_user_posts(%Scope{user: %User{id: viewer_id}}, %{id: profile_user_id}) do
    community_ids =
      viewer_id |> shared_communities(profile_user_id) |> exclude(:select) |> select([c], c.id)

    Post
    |> scored(PostVote, :post_id, viewer_id)
    |> where([p], p.author_id == ^profile_user_id and p.community_id in subquery(community_ids))
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> preload(:community)
    |> Repo.all()
  end

  defp shared_communities(viewer_id, profile_user_id) do
    viewer_id
    |> accessible_communities()
    |> join(:inner, [c], m in CommunityMembership,
      on: m.community_id == c.id and m.user_id == ^profile_user_id
    )
  end

  @doc "Sums post and comment votes received by a user in active communities shared with the viewer."
  def user_karma(%Scope{user: %User{id: viewer_id}}, %{id: profile_user_id}) do
    community_ids =
      viewer_id |> shared_communities(profile_user_id) |> exclude(:select) |> select([c], c.id)

    post_karma =
      Repo.one(
        from v in PostVote,
          join: p in Post,
          on: p.id == v.post_id,
          where: p.author_id == ^profile_user_id and p.community_id in subquery(community_ids),
          select: coalesce(sum(v.value), 0)
      )

    comment_karma =
      Repo.one(
        from v in CommentVote,
          join: c in Comment,
          on: c.id == v.comment_id,
          join: p in Post,
          on: p.id == c.post_id,
          where: c.author_id == ^profile_user_id and p.community_id in subquery(community_ids),
          select: coalesce(sum(v.value), 0)
      )

    post_karma + comment_karma
  end

  @doc "Gets a post only within an accessible community."
  def get_post!(%Scope{user: %User{id: user_id}} = scope, %Community{id: community_id}, id) do
    get_community!(scope, community_id)

    Post
    |> scored(PostVote, :post_id, user_id)
    |> where([p], p.community_id == ^community_id and p.id == ^id)
    |> Repo.one!()
  end

  @doc "Gets a post within an accessible community, returning :not_found when unavailable."
  def get_post(%Scope{user: %User{id: user_id}} = scope, %Community{id: community_id}, id) do
    with {:ok, _community} <- get_community(scope, community_id),
         {:ok, id} <- cast_id(id) do
      Post
      |> scored(PostVote, :post_id, user_id)
      |> where([p], p.community_id == ^community_id and p.id == ^id)
      |> Repo.one()
      |> fetch_result()
    end
  end

  def change_post(%Scope{} = scope, %Community{id: id}, attrs \\ %{}) do
    with {:ok, _community} <- get_community(scope, id) do
      Post.changeset(%Post{community_id: id, author_id: scope.user.id}, attrs)
    end
  end

  def create_post(scope, %Community{id: id}, attrs) do
    mutate(scope, id, fn _community, _caller ->
      %Post{community_id: id, author_id: scope.user.id}
      |> Post.changeset(attrs)
      |> persist(:insert)
    end)
  end

  @doc "Lists comments in thread order, with authors, scores and display depth."
  def list_comments(%Scope{user: %User{id: user_id}} = scope, %Post{} = post) do
    with {:ok, post} <- get_post(scope, %Community{id: post.community_id}, post.id) do
      Comment
      |> scored(CommentVote, :comment_id, user_id)
      |> where([c], c.post_id == ^post.id)
      |> order_by([c], asc: c.id)
      |> Repo.all()
      |> Enum.group_by(& &1.parent_id)
      |> thread(nil, 0)
    end
  end

  def change_comment(scope, %Post{} = post, attrs \\ %{}) do
    with {:ok, post} <- get_post(scope, %Community{id: post.community_id}, post.id) do
      Comment.changeset(%Comment{post_id: post.id, author_id: scope.user.id}, attrs)
    end
  end

  @doc "Creates a comment or reply. Parent IDs are checked against the actual post."
  def create_comment(scope, %Post{id: id}, attrs, parent_id \\ nil) do
    with {:ok, post} <- fetch_result(Repo.get(Post, id)) do
      mutate(scope, post.community_id, fn _community, _caller ->
        authorize_parent!(id, parent_id)

        %Comment{post_id: id, author_id: scope.user.id, parent_id: parent_id}
        |> Comment.changeset(attrs)
        |> persist(:insert)
      end)
    end
  end

  defp authorize_parent!(_post_id, nil), do: :ok

  defp authorize_parent!(post_id, parent_id) do
    case cast_id(parent_id) do
      {:ok, parent_id} ->
        authorize!(
          Repo.exists?(from c in Comment, where: c.id == ^parent_id and c.post_id == ^post_id)
        )

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  @doc "Sets a post vote to 1 or -1; 0 clears it. One vote per user is enforced."
  def vote_post(scope, %Post{id: id}, value) do
    with {:ok, post} <- fetch_result(Repo.get(Post, id)) do
      mutate(scope, post.community_id, fn _community, _caller ->
        set_vote(PostVote, :post_id, id, scope.user.id, value)
      end)
    end
  end

  @doc "Sets a comment vote to 1 or -1; 0 clears it."
  def vote_comment(scope, %Comment{id: id}, value) do
    with {:ok, comment} <- fetch_result(Repo.get(Comment, id)),
         {:ok, post} <- fetch_result(Repo.get(Post, comment.post_id)) do
      mutate(scope, post.community_id, fn _community, _caller ->
        set_vote(CommentVote, :comment_id, id, scope.user.id, value)
      end)
    end
  end

  defp set_vote(schema, key, id, user_id, 0) do
    Repo.delete_all(from v in schema, where: field(v, ^key) == ^id and v.user_id == ^user_id)
    :cleared
  end

  defp set_vote(schema, key, id, user_id, value) do
    changeset =
      schema.changeset(struct(schema, [{key, id}, {:user_id, user_id}]), %{value: value})

    case Repo.insert(changeset,
           on_conflict: {:replace, [:value, :updated_at]},
           conflict_target: [key, :user_id]
         ) do
      {:ok, vote} -> vote
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp scored(schema, votes, key, user_id) do
    totals =
      from v in votes,
        group_by: field(v, ^key),
        select: %{target_id: field(v, ^key), score: sum(v.value)}

    from record in schema,
      left_join: total in subquery(totals),
      on: total.target_id == record.id,
      left_join: mine in ^votes,
      on: field(mine, ^key) == record.id and mine.user_id == ^user_id,
      select_merge: %{score: coalesce(total.score, 0), my_vote: coalesce(mine.value, 0)},
      preload: [:author]
  end

  defp thread(grouped, parent_id, depth) do
    Enum.flat_map(Map.get(grouped, parent_id, []), fn comment ->
      [%{comment | depth: depth} | thread(grouped, comment.id, depth + 1)]
    end)
  end

  defp accessible_communities(user_id) do
    from c in Community,
      join: m in CommunityMembership,
      on: m.community_id == c.id,
      where: m.user_id == ^user_id and is_nil(c.deleted_at),
      select: c
  end

  defp caller_membership(%Scope{user: %User{id: user_id}}, community_id) do
    Repo.get_by(CommunityMembership, community_id: community_id, user_id: user_id)
  end

  # Serialize all mutations for a community before checking current permissions.
  defp mutate(scope, id, fun, notify? \\ true) do
    result =
      transaction(fn ->
        community =
          Repo.one(
            from c in Community, where: c.id == ^id and is_nil(c.deleted_at), lock: "FOR UPDATE"
          )

        authorize!(community != nil)
        caller = caller_membership(scope, id)
        authorize!(caller != nil)
        fun.(community, caller)
      end)

    # Publish after the transaction succeeds, never including private content.
    if notify? and match?({:ok, _}, result) do
      Phoenix.PubSub.broadcast(Arcanum.PubSub, community_topic(id), {:community_changed, id})
    end

    result
  end

  defp get_membership!(community_id, id) do
    membership = Repo.get_by(CommunityMembership, id: id, community_id: community_id)
    authorize!(membership != nil)
    membership
  end

  defp authorize_role!(caller, role) do
    authorize!(
      (caller.role == :owner and role in [:admin, :member]) or
        (caller.role == :admin and role == :member)
    )
  end

  defp authorize!(true), do: :ok
  defp authorize!(false), do: Repo.rollback(:unauthorized)

  defp persist(changeset, operation) do
    case apply(Repo, operation, [changeset]) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp transaction(fun), do: Repo.transaction(fun)
end
