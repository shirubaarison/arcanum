defmodule Arcanum.Communities.CommunityMembership do
  use Ecto.Schema
  import Ecto.Changeset

  schema "community_memberships" do
    field :role, Ecto.Enum, values: [:owner, :admin, :member], default: :member

    belongs_to :community, Arcanum.Communities.Community
    belongs_to :user, Arcanum.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Validates a membership with user_id and community_id set by trusted application code.
  Role changes must be authorized by the caller.
  """
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role])
    |> validate_required([:community_id, :user_id, :role])
    |> foreign_key_constraint(:community_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:community_id, :user_id])
    |> check_constraint(:role, name: :community_memberships_role_check)
  end
end
