defmodule Arcanum.Communities.CommunityTest do
  use Arcanum.DataCase, async: true

  alias Arcanum.Communities.Community

  test "requires a name" do
    changeset = Community.changeset(%Community{}, %{name: " "})
    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "limits name length" do
    changeset = Community.changeset(%Community{}, %{name: String.duplicate("a", 256)})
    assert %{name: ["should be at most 255 character(s)"]} = errors_on(changeset)
  end

  test "persists a community with standard timestamps and optional description" do
    community = %Community{} |> Community.changeset(%{name: "Elixir"}) |> Repo.insert!()

    assert community.name == "Elixir"
    assert community.description == nil
    assert community.deleted_at == nil
    assert %DateTime{} = community.inserted_at
    assert %DateTime{} = community.updated_at
  end

  test "soft deletion preserves the community record" do
    community = %Community{} |> Community.changeset(%{name: "Elixir"}) |> Repo.insert!()
    deleted = community |> Community.soft_delete_changeset() |> Repo.update!()

    assert %DateTime{} = deleted.deleted_at
    assert Repo.get!(Community, community.id).deleted_at == deleted.deleted_at
  end

  test "ordinary attributes cannot set deleted_at" do
    changeset =
      Community.changeset(%Community{}, %{name: "Elixir", deleted_at: DateTime.utc_now(:second)})

    assert get_field(changeset, :deleted_at) == nil
  end
end
