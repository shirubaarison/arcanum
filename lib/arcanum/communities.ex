defmodule Arcanum.Communities do
  @moduledoc """
  Community operations scoped to the authenticated caller.

  Members can read their communities. Owners and admins can edit communities
  and manage ordinary members. Only owners can assign admins or soft-delete
  communities. Owner transfer is not supported.

  Mutations return `{:error, :unauthorized}` for inaccessible communities.
  """

  import Ecto.Query

  alias Arcanum.Accounts.{Scope, User}
  alias Arcanum.Communities.{Community, CommunityMembership}
  alias Arcanum.Repo

  @doc "Lists the caller's active communities."
  def list_communities(%Scope{user: %User{id: user_id}}) do
    user_id |> accessible_communities() |> order_by([c], asc: c.id) |> Repo.all()
  end

  @doc "Gets an active community belonging to the caller, or raises Ecto.NoResultsError."
  def get_community!(%Scope{user: %User{id: user_id}}, id) do
    user_id |> accessible_communities() |> Repo.get!(id)
  end

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
    community = get_community!(scope, id)
    membership = caller_membership(scope, id)

    if membership.role in [:owner, :admin] do
      Community.changeset(community, attrs)
    else
      {:error, :unauthorized}
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
    get_community!(scope, id)

    Repo.all(
      from m in CommunityMembership,
        where: m.community_id == ^id,
        order_by: [asc: m.id],
        preload: [:user]
    )
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
  defp mutate(scope, id, fun) do
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
