defmodule Arcanum.Communities.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "community_posts" do
    field :title, :string
    field :body, :string
    field :score, :integer, virtual: true, default: 0
    field :my_vote, :integer, virtual: true, default: 0
    belongs_to :community, Arcanum.Communities.Community
    belongs_to :author, Arcanum.Accounts.User
    has_many :comments, Arcanum.Communities.Comment
    has_many :votes, Arcanum.Communities.PostVote
    timestamps(type: :utc_datetime)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :body])
    |> validate_required([:title, :body, :community_id, :author_id])
    |> validate_length(:title, max: 255)
    |> validate_length(:body, max: 50_000)
    |> foreign_key_constraint(:community_id)
    |> foreign_key_constraint(:author_id)
  end
end
