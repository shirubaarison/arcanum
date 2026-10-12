defmodule Arcanum.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms) do
      add :community_id, references(:communities, on_delete: :delete_all), null: false
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:rooms, [:community_id])
  end
end
