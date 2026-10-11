defmodule ArcanumWeb.UserLive.Profile do
  use ArcanumWeb, :live_view

  alias Arcanum.{Accounts, Communities}
  alias Arcanum.Communities.Community
  alias ArcanumWeb.FailureLog

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :subscribed_community_ids, MapSet.new())}
  end

  @impl true
  def handle_params(%{"username" => username}, _uri, socket) do
    case Accounts.get_user_profile(socket.assigns.current_scope, username) do
      {:ok, profile} ->
        {:noreply,
         socket
         |> assign(profile: profile, page_title: profile.username)
         |> refresh()}

      {:error, reason} ->
        FailureLog.log("user profile lookup", reason)

        {:noreply,
         socket
         |> put_flash(:error, "User not found.")
         |> push_navigate(to: ~p"/communities")}
    end
  end

  @impl true
  def handle_info({:community_changed, _id}, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    scope = socket.assigns.current_scope
    profile = socket.assigns.profile
    communities = Communities.list_communities(scope)
    posts = Communities.list_user_posts(scope, profile)

    socket
    |> sync_subscriptions(communities)
    |> assign(post_count: length(posts), karma: Communities.user_karma(scope, profile))
    |> stream(:posts, posts, reset: true)
  end

  defp sync_subscriptions(socket, communities) do
    if connected?(socket) do
      scope = socket.assigns.current_scope
      previous = socket.assigns.subscribed_community_ids
      current = MapSet.new(communities, & &1.id)

      for id <- MapSet.difference(previous, current) do
        Communities.unsubscribe_community(scope, %Community{id: id})
      end

      subscribed =
        Enum.reduce(
          MapSet.difference(current, previous),
          MapSet.intersection(previous, current),
          fn id, ids -> subscribe(scope, id, ids) end
        )

      assign(socket, :subscribed_community_ids, subscribed)
    else
      socket
    end
  end

  defp subscribe(scope, id, ids) do
    case Communities.subscribe_community(scope, %Community{id: id}) do
      :ok ->
        MapSet.put(ids, id)

      {:error, reason} ->
        FailureLog.log("profile community subscription", reason)
        ids
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} community>
      <.link navigate={~p"/communities"} class="text-xs text-stone-500 hover:underline">
        ← communities
      </.link>
      <section id="user-profile" class="mt-4 border-b border-stone-200 pb-6">
        <div class="flex flex-wrap items-center gap-3">
          <h1 id="profile-username" class="break-all text-xl font-bold">{@profile.username}</h1>
          <.link
            :if={@profile.id == @current_scope.user.id}
            id="profile-settings"
            navigate={~p"/users/settings"}
            class="text-xs text-stone-500 transition-colors hover:text-blue-600 hover:underline"
          >edit account</.link>
        </div>
        <p id="profile-joined" class="mt-2 text-xs text-stone-500">
          Joined {Calendar.strftime(@profile.inserted_at, "%b %d, %Y")}
        </p>
        <p
          class="mt-3 text-sm text-stone-600"
          title="Net post and comment votes in your shared communities"
        >
          <span id="profile-karma" class="font-semibold tabular-nums text-blue-600">{@karma}</span>
          karma
        </p>
      </section>

      <div class="mt-6 flex items-baseline gap-2">
        <h2 class="font-bold">Posts</h2>
        <span id="profile-post-count" class="text-xs text-stone-500">{@post_count}</span>
      </div>
      <div id="profile-posts" phx-update="stream" class="mt-5 space-y-5">
        <p id="profile-posts-empty" class="hidden text-stone-500 only:block">
          No posts to show in your shared communities.
        </p>
        <article :for={{id, post} <- @streams.posts} id={id} class="min-w-0">
          <.link
            id={"profile-post-#{post.id}"}
            navigate={~p"/communities/#{post.community}/posts/#{post}"}
            class="break-words font-medium transition-colors hover:text-blue-600 hover:underline"
          >{post.title}</.link>
          <p class="mt-1 text-xs text-stone-500">
            <span id={"profile-post-score-#{post.id}"}>{post.score} points</span>
            ·
            <.link
              id={"profile-post-community-#{post.id}"}
              navigate={~p"/communities/#{post.community}"}
              class="break-words hover:underline"
            >{post.community.name}</.link>
            · {Calendar.strftime(post.inserted_at, "%b %d, %Y")}
          </p>
        </article>
      </div>
    </Layouts.app>
    """
  end
end
