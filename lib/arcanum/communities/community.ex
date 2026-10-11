defmodule Arcanum.Communities.Community do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Phoenix.Param, key: :name}

  schema "communities" do
    field :name, :string
    field :description, :string
    field :deleted_at, :utc_datetime

    has_many :community_memberships, Arcanum.Communities.CommunityMembership
    has_many :members, through: [:community_memberships, :user]
    has_many :posts, Arcanum.Communities.Post

    timestamps(type: :utc_datetime)
  end

  def changeset(community, attrs) do
    community
    |> cast(attrs, [:name, :description])
    |> update_change(:name, fn
      nil -> nil
      name -> String.trim(name)
    end)
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> validate_format(:name, ~r/^[^\/]+$/, message: "must not contain slashes")
    |> validate_change(:name, fn :name, name ->
      if String.downcase(name) == "new", do: [name: "is reserved"], else: []
    end)
    |> unique_constraint(:name)
  end

  def soft_delete_changeset(community) do
    change(community, deleted_at: DateTime.utc_now(:second))
  end
end
