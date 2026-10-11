defmodule Arcanum.Communities.Community do
  use Ecto.Schema
  import Ecto.Changeset

  schema "communities" do
    field :name, :string
    field :description, :string
    field :deleted_at, :utc_datetime

    has_many :community_memberships, Arcanum.Communities.CommunityMembership
    has_many :members, through: [:community_memberships, :user]

    timestamps(type: :utc_datetime)
  end

  def changeset(community, attrs) do
    community
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
  end

  def soft_delete_changeset(community) do
    change(community, deleted_at: DateTime.utc_now(:second))
  end
end
