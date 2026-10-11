defmodule Arcanum.Communities.PubSubTest do
  use Arcanum.DataCase, async: true

  import Arcanum.AccountsFixtures
  alias Arcanum.Communities

  setup do
    scope = user_scope_fixture()
    {:ok, community} = Communities.create_community(scope, %{name: "Private"})
    :ok = Communities.subscribe_community(scope, community)
    %{scope: scope, community: community}
  end

  test "successful posts, comments and votes broadcast only the community ID", context do
    %{scope: scope, community: %{id: id} = community} = context

    {:ok, post} =
      Communities.create_post(scope, community, %{title: "Hello", body: "Private text"})

    assert_receive {:community_changed, ^id}
    {:ok, comment} = Communities.create_comment(scope, post, %{body: "Private comment"})
    assert_receive {:community_changed, ^id}
    {:ok, _} = Communities.vote_post(scope, post, 1)
    assert_receive {:community_changed, ^id}
    {:ok, _} = Communities.vote_comment(scope, comment, -1)
    assert_receive {:community_changed, ^id}
    {:ok, _} = Communities.vote_post(scope, post, 0)
    assert_receive {:community_changed, ^id}
  end

  test "failed writes and member searches do not broadcast", %{scope: scope, community: community} do
    assert {:error, _} = Communities.create_post(scope, community, %{title: "", body: ""})
    assert {:ok, _} = Communities.search_available_users(scope, community)
    refute_receive {:community_changed, _}
  end

  test "subscriptions require membership and can be removed", %{
    scope: scope,
    community: community
  } do
    outsider = user_scope_fixture()

    assert_raise Ecto.NoResultsError, fn ->
      Communities.subscribe_community(outsider, community)
    end

    :ok = Communities.unsubscribe_community(scope, community)
    {:ok, _} = Communities.create_post(scope, community, %{title: "Hello", body: "Text"})
    refute_receive {:community_changed, _}
  end
end
