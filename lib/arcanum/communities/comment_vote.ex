defmodule Arcanum.Communities.CommentVote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "community_comment_votes" do
    field :value, :integer
    belongs_to :comment, Arcanum.Communities.Comment
    belongs_to :user, Arcanum.Accounts.User
    timestamps(type: :utc_datetime)
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:value])
    |> validate_required([:comment_id, :user_id, :value])
    |> validate_inclusion(:value, [-1, 1])
    |> foreign_key_constraint(:comment_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:comment_id, :user_id])
    |> check_constraint(:value, name: :community_comment_votes_value_check)
  end
end
