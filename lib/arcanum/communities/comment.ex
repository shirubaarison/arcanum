defmodule Arcanum.Communities.Comment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "community_comments" do
    field :body, :string
    field :score, :integer, virtual: true, default: 0
    field :my_vote, :integer, virtual: true, default: 0
    field :depth, :integer, virtual: true, default: 0
    belongs_to :post, Arcanum.Communities.Post
    belongs_to :author, Arcanum.Accounts.User
    belongs_to :parent, __MODULE__
    has_many :replies, __MODULE__, foreign_key: :parent_id
    has_many :votes, Arcanum.Communities.CommentVote
    timestamps(type: :utc_datetime)
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body])
    |> validate_required([:body, :post_id, :author_id])
    |> validate_length(:body, max: 10_000)
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:author_id)
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:parent_id, name: :community_comments_parent_post_fkey)
  end
end
