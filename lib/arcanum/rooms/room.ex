defmodule Arcanum.Rooms.Room do
  use Ecto.Schema
  import Ecto.Changeset

  schema "rooms" do
    field :name, :string
    belongs_to :community, Arcanum.Communities.Community
    has_many :messages, Arcanum.Rooms.Message
    timestamps(type: :utc_datetime)
  end

  def changeset(room, attrs) do
    room
    |> cast(attrs, [:name])
    |> update_change(:name, fn
      nil -> nil
      name -> String.trim(name)
    end)
    |> validate_required([:name, :community_id])
    |> validate_length(:name, max: 255)
    |> foreign_key_constraint(:community_id)
  end
end
