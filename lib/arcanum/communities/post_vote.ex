defmodule Arcanum.Communities.PostVote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "community_post_votes" do
    field :value, :integer
    belongs_to :post, Arcanum.Communities.Post
    belongs_to :user, Arcanum.Accounts.User
    timestamps(type: :utc_datetime)
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:value])
    |> validate_required([:post_id, :user_id, :value])
    |> validate_inclusion(:value, [-1, 1])
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:post_id, :user_id])
    |> check_constraint(:value, name: :community_post_votes_value_check)
  end
end
