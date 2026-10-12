defmodule Arcanum.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :message, :text, null: false
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :room_id, references(:rooms, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:room_id, :inserted_at])
    create index(:messages, [:user_id])
  end
end
