defmodule ArcanumWeb.CommunityLive.Edit do
  use ArcanumWeb, :live_view

  alias Arcanum.Communities
  alias Arcanum.Communities.{Community, CommunityMembership}
  alias ArcanumWeb.FailureLog

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:member_query, "")
     |> stream_configure(:available_users, dom_id: &"available-user-#{&1.id}")}
  end

  @impl true
  def handle_params(%{"name" => name}, _uri, socket) do
    case Communities.get_community_by_name(socket.assigns.current_scope, name) do
      {:ok, community} -> {:noreply, load(socket, community.id)}
      {:error, reason} -> {:noreply, unavailable(socket, reason)}
    end
  end

  defp load(socket, id) do
    scope = socket.assigns.current_scope

    with {:ok, community} <- Communities.get_community(scope, id),
         memberships when is_list(memberships) <- Communities.list_memberships(scope, community),
         %CommunityMembership{} = caller <- Enum.find(memberships, &(&1.user_id == scope.user.id)) do
      socket
      |> assign(
        community: community,
        page_title: community.name,
        role: caller.role,
        form: to_form(Community.changeset(community, %{})),
        member_form: to_form(member_changeset(%{query: socket.assigns.member_query}), as: :member)
      )
      |> stream(:memberships, memberships, reset: true)
      |> refresh_available_users()
    else
      {:error, reason} -> unavailable(socket, reason)
      nil -> unavailable(socket, :not_found)
    end
  end

  defp unavailable(socket, reason) do
    FailureLog.log("community settings lookup", reason)

    socket
    |> put_flash(:error, "Community not found or you don't have access.")
    |> push_navigate(to: ~p"/communities")
  end

  @impl true
  def handle_event("validate", %{"community" => attrs}, socket) do
    changeset = Community.changeset(socket.assigns.community, attrs)
    {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :validate)))}
  end

  def handle_event("save", %{"community" => attrs}, socket) do
    case Communities.update_community(
           socket.assigns.current_scope,
           socket.assigns.community,
           attrs
         ) do
      {:ok, community} ->
        {:noreply,
         socket
         |> load(community.id)
         |> put_flash(:info, "Community updated.")
         |> push_patch(to: ~p"/communities/#{community}/edit")}

      {:error, %Ecto.Changeset{} = changeset} ->
        FailureLog.log("update community", changeset)
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, reason} ->
        denied(socket, reason)
    end
  end

  def handle_event("delete", _params, socket) do
    case Communities.delete_community(socket.assigns.current_scope, socket.assigns.community) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Community deleted.") |> push_navigate(to: ~p"/communities")}

      {:error, reason} ->
        denied(socket, reason)
    end
  end

  def handle_event("search_members", %{"member" => attrs}, socket) do
    changeset = member_changeset(attrs)
    query = Ecto.Changeset.get_field(changeset, :query) || ""

    {:noreply,
     socket
     |> assign(member_query: query, member_form: to_form(changeset, as: :member))
     |> refresh_available_users()}
  end

  def handle_event("add_member", %{"id" => id}, socket) do
    result =
      case Integer.parse(id) do
        {user_id, ""} when user_id > 0 ->
          Communities.add_member_by_id(
            socket.assigns.current_scope,
            socket.assigns.community,
            user_id
          )

        _ ->
          {:error, :user_not_found}
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket |> load(socket.assigns.community.id) |> put_flash(:info, "Member added.")}

      {:error, :unauthorized} ->
        denied(socket, :unauthorized)

      {:error, reason} ->
        FailureLog.log("add member", reason)

        {:noreply,
         socket
         |> refresh_available_users()
         |> put_flash(:error, "Could not add this account. It may already be a member.")}
    end
  end

  def handle_event(event, %{"id" => id} = params, socket)
      when event in ["remove_member", "change_role"] do
    scope = socket.assigns.current_scope

    membership =
      case Communities.list_memberships(scope, socket.assigns.community) do
        memberships when is_list(memberships) -> Enum.find(memberships, &(to_string(&1.id) == id))
        {:error, _reason} -> nil
      end

    result =
      case {event, membership} do
        {_, nil} ->
          {:error, :unauthorized}

        {"remove_member", %CommunityMembership{} = member} ->
          Communities.remove_member(scope, member)

        {"change_role", %CommunityMembership{} = member} ->
          Communities.update_membership(scope, member, %{role: params["role"]})
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket |> load(socket.assigns.community.id) |> put_flash(:info, "Membership updated.")}

      {:error, reason} ->
        denied(socket, reason)
    end
  end

  defp denied(socket, reason) do
    FailureLog.log("community management", reason)
    {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}
  end

  defp member_changeset(attrs) do
    {%{}, %{query: :string}}
    |> Ecto.Changeset.cast(attrs, [:query])
  end

  defp refresh_available_users(socket) do
    case Communities.search_available_users(
           socket.assigns.current_scope,
           socket.assigns.community,
           socket.assigns.member_query
         ) do
      {:ok, users} ->
        stream(socket, :available_users, users, reset: true)

      {:error, reason} ->
        FailureLog.log("search members", reason)
        stream(socket, :available_users, [], reset: true)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} community>
      <.link navigate={~p"/communities/#{@community}"} class="text-xs text-stone-500 hover:underline">← posts</.link>
      <h1 id="community-name" class="mt-3 text-xl font-bold">{@community.name}</h1>
      <p class="mt-2 whitespace-pre-wrap break-words text-stone-600">{@community.description}</p>
      <p class="mt-2 text-xs text-stone-500">your role: {@role}</p>

      <section :if={@role in [:owner, :admin]} class="mt-8 max-w-xl">
        <h2 class="mb-3 font-bold">Edit community</h2>
        <.form
          for={@form}
          id="community-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.input field={@form[:name]} label="Name" required maxlength="255" class="community-input" />
          <.input
            field={@form[:description]}
            type="textarea"
            label="Description"
            class="community-input"
          />
          <button id="save-community" class="community-button" phx-disable-with="Saving...">Save</button>
        </.form>
      </section>

      <section class="mt-8">
        <h2 class="mb-3 font-bold">Members</h2>
        <div id="memberships" phx-update="stream" class="divide-y divide-stone-200">
          <div
            :for={{id, member} <- @streams.memberships}
            id={id}
            class="flex flex-wrap items-center gap-3 py-3"
          >
            <.link
              id={"member-profile-#{member.id}"}
              navigate={~p"/#{member.user.username}"}
              class="break-all hover:underline"
            >{member.user.username}</.link>
            <span class="text-xs text-stone-500">{member.role}</span>
            <div
              :if={
                (@role == :owner and member.role != :owner) or
                  (@role == :admin and member.role == :member)
              }
              class="flex gap-3 text-xs"
            >
              <button
                :if={@role == :owner}
                id={"role-#{member.id}"}
                phx-click="change_role"
                phx-value-id={member.id}
                phx-value-role={if(member.role == :admin, do: "member", else: "admin")}
                class="cursor-pointer hover:underline"
              >{if(member.role == :admin, do: "make member", else: "make admin")}</button>
              <button
                id={"remove-#{member.id}"}
                phx-click="remove_member"
                phx-value-id={member.id}
                data-confirm="Remove this member?"
                class="cursor-pointer text-red-700 hover:underline"
              >remove</button>
            </div>
          </div>
        </div>
        <section :if={@role in [:owner, :admin]} id="member-picker" class="mt-6 max-w-xl">
          <h3 class="font-bold">Add members</h3>
          <.form
            for={@member_form}
            id="member-form"
            phx-change="search_members"
            phx-submit="search_members"
            class="mt-4 max-w-xl space-y-3"
          >
            <.input
              field={@member_form[:query]}
              type="search"
              label="Search usernames"
              placeholder="Type a username..."
              phx-debounce="250"
              class="community-input"
            />
          </.form>
          <div id="available-users" phx-update="stream" class="mt-3 divide-y divide-stone-200">
            <p id="available-users-empty" class="hidden py-3 text-stone-500 only:block">
              No accounts found.
            </p>
            <button
              :for={{id, user} <- @streams.available_users}
              id={id}
              type="button"
              phx-click="add_member"
              phx-value-id={user.id}
              phx-disable-with="Adding..."
              class="flex w-full cursor-pointer items-center justify-between gap-3 px-2 py-3 text-left transition-colors hover:bg-blue-50 disabled:opacity-50"
            >
              <span class="break-all">{user.username}</span>
              <span class="text-xs text-blue-600">add</span>
            </button>
          </div>
        </section>
      </section>
      <button
        :if={@role == :owner}
        id="delete-community"
        phx-click="delete"
        data-confirm="Delete this community? Members will no longer be able to access it."
        class="mt-10 cursor-pointer text-xs text-red-700 hover:underline"
      >delete community</button>
    </Layouts.app>
    """
  end
end
