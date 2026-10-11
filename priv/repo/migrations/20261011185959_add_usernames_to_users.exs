defmodule Arcanum.Repo.Migrations.AddUsernamesToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :username, :citext
    end

    execute "UPDATE users SET username = 'user_' || id::text"

    alter table(:users) do
      modify :username, :citext, null: false
    end

    create unique_index(:users, [:username])
  end

  def down do
    drop unique_index(:users, [:username])

    alter table(:users) do
      remove :username
    end
  end
end
