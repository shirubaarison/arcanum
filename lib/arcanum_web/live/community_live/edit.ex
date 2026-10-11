defmodule ArcanumWeb.CommunityLive.Edit do
  use ArcanumWeb, :live_view

  alias Arcanum.Communities
  alias Arcanum.Communities.CommunityMembership

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    {:noreply, load(socket, id)}
  rescue
    _ in [Ecto.NoResultsError, Ecto.Query.CastError] ->
      {:noreply,
       socket
       |> put_flash(:error, "Community not found or you don't have access.")
       |> push_navigate(to: ~p"/communities")}
  end

  defp load(socket, id) do
    scope = socket.assigns.current_scope
    community = Communities.get_community!(scope, id)
    memberships = Communities.list_memberships(scope, community)
    caller = Enum.find(memberships, &(&1.user_id == scope.user.id))

    socket
    |> assign(
      community: community,
      page_title: community.name,
      role: caller.role,
      form: to_form(Arcanum.Communities.Community.changeset(community, %{})),
      member_form: to_form(member_changeset(%{}), as: :member)
    )
    |> stream(:memberships, memberships, reset: true)
  end

  @impl true
  def handle_event("validate", %{"community" => attrs}, socket) do
    changeset = Arcanum.Communities.Community.changeset(socket.assigns.community, attrs)
    {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :validate)))}
  end

  def handle_event("save", %{"community" => attrs}, socket) do
    case Communities.update_community(
           socket.assigns.current_scope,
           socket.assigns.community,
           attrs
         ) do
      {:ok, community} ->
        {:noreply, socket |> load(community.id) |> put_flash(:info, "Community updated.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, _} ->
        denied(socket)
    end
  end

  def handle_event("delete", _params, socket) do
    case Communities.delete_community(socket.assigns.current_scope, socket.assigns.community) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Community deleted.") |> push_navigate(to: ~p"/communities")}

      {:error, _} ->
        denied(socket)
    end
  end

  def handle_event("add_member", %{"member" => attrs}, socket) do
    changeset = member_changeset(attrs)

    result =
      if changeset.valid? do
        Communities.add_member_by_email(
          socket.assigns.current_scope,
          socket.assigns.community,
          Ecto.Changeset.get_field(changeset, :email)
        )
      else
        {:error, Map.put(changeset, :action, :insert)}
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket |> load(socket.assigns.community.id) |> put_flash(:info, "Member added.")}

      {:error, :unauthorized} ->
        denied(socket)

      {:error, reason} ->
        changeset =
          if not changeset.valid? do
            Map.put(changeset, :action, :insert)
          else
            message =
              if reason == :user_not_found,
                do: "No registered user with that email.",
                else: "Could not add this member. They may already belong to this community."

            changeset |> Ecto.Changeset.add_error(:email, message) |> Map.put(:action, :insert)
          end

        {:noreply, assign(socket, :member_form, to_form(changeset, as: :member))}
    end
  end

  def handle_event(event, %{"id" => id} = params, socket)
      when event in ["remove_member", "change_role"] do
    scope = socket.assigns.current_scope

    membership =
      Enum.find(
        Communities.list_memberships(scope, socket.assigns.community),
        &(to_string(&1.id) == id)
      )

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

      {:error, _} ->
        denied(socket)
    end
  end

  defp denied(socket),
    do: {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}

  defp member_changeset(attrs) do
    {%{}, %{email: :string}}
    |> Ecto.Changeset.cast(attrs, [:email])
    |> Ecto.Changeset.validate_required([:email])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/)
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
            <span class="break-all">{member.user.username}</span>
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
        <.form
          :if={@role in [:owner, :admin]}
          for={@member_form}
          id="member-form"
          phx-submit="add_member"
          class="mt-4 max-w-xl space-y-3"
        >
          <.input
            field={@member_form[:email]}
            type="email"
            label="Add a registered user by email"
            required
            class="community-input"
          />
          <button id="add-member" class="community-button" phx-disable-with="Adding...">Add member</button>
        </.form>
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
