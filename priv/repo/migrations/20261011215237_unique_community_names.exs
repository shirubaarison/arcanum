defmodule Arcanum.Repo.Migrations.UniqueCommunityNames do
  use Ecto.Migration

  def change do
    create unique_index(:communities, ["lower(name)"], name: :communities_name_index)
  end
end
