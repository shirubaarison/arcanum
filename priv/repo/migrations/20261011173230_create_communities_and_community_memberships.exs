defmodule Arcanum.Repo.Migrations.CreateCommunitiesAndCommunityMemberships do
  use Ecto.Migration

  def change do
    create table(:communities) do
      add :name, :string, null: false
      add :description, :text
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create table(:community_memberships) do
      add :community_id, references(:communities, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:community_memberships, [:community_id, :user_id])
    create index(:community_memberships, [:user_id])

    create constraint(:community_memberships, :community_memberships_role_check,
             check: "role IN ('owner', 'admin', 'member')"
           )
  end
end
