defmodule Arcanum.Repo.Migrations.CreateCommunityPostsCommentsAndVotes do
  use Ecto.Migration

  def change do
    create table(:community_posts) do
      add :community_id, references(:communities, on_delete: :delete_all), null: false
      add :author_id, references(:users, on_delete: :restrict), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:community_posts, [:community_id, :inserted_at])
    create index(:community_posts, [:author_id])

    create table(:community_comments) do
      add :post_id, references(:community_posts, on_delete: :delete_all), null: false
      add :author_id, references(:users, on_delete: :restrict), null: false
      add :parent_id, :bigint
      add :body, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:community_comments, [:post_id, :inserted_at])
    create index(:community_comments, [:author_id])
    create index(:community_comments, [:parent_id])
    create unique_index(:community_comments, [:id, :post_id])

    execute """
            ALTER TABLE community_comments ADD CONSTRAINT community_comments_parent_post_fkey
            FOREIGN KEY (parent_id, post_id) REFERENCES community_comments(id, post_id)
            ON DELETE CASCADE
            """,
            "ALTER TABLE community_comments DROP CONSTRAINT community_comments_parent_post_fkey"

    create table(:community_post_votes) do
      add :post_id, references(:community_posts, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :value, :integer, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:community_post_votes, [:post_id, :user_id])
    create index(:community_post_votes, [:user_id])

    create constraint(:community_post_votes, :community_post_votes_value_check,
             check: "value IN (-1, 1)"
           )

    create table(:community_comment_votes) do
      add :comment_id, references(:community_comments, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :value, :integer, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:community_comment_votes, [:comment_id, :user_id])
    create index(:community_comment_votes, [:user_id])

    create constraint(:community_comment_votes, :community_comment_votes_value_check,
             check: "value IN (-1, 1)"
           )
  end
end
