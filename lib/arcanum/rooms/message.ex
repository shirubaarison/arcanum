defmodule Arcanum.Rooms.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :message, :string
    belongs_to :user, Arcanum.Accounts.User
    belongs_to :room, Arcanum.Rooms.Room
    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:message])
    |> validate_required([:message, :user_id, :room_id])
    |> validate_length(:message, max: 50_000)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:room_id)
  end
end
