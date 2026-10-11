defmodule ArcanumWeb.CommunityLive.Index do
  use ArcanumWeb, :live_view

  alias Arcanum.Communities
  alias Arcanum.Communities.Community

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     stream(socket, :communities, Communities.list_communities(socket.assigns.current_scope))}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(
       :page_title,
       if(socket.assigns.live_action == :new, do: "Create community", else: "Communities")
     )
     |> assign(:form, to_form(Community.changeset(%Community{}, %{})))}
  end

  @impl true
  def handle_event("validate", %{"community" => attrs}, socket) do
    changeset = Community.changeset(%Community{}, attrs) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"community" => attrs}, socket) do
    case Communities.create_community(socket.assigns.current_scope, attrs) do
      {:ok, community} ->
        {:noreply,
         socket
         |> put_flash(:info, "Community created.")
         |> push_navigate(to: ~p"/communities/#{community}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} community>
      <%= if @live_action == :new do %>
        <h1 class="mb-5 text-lg font-bold">Create a community</h1>
        <.form
          for={@form}
          id="community-form"
          phx-change="validate"
          phx-submit="save"
          class="max-w-xl space-y-4"
        >
          <.input field={@form[:name]} label="Name" required maxlength="255" class="community-input" />
          <.input
            field={@form[:description]}
            type="textarea"
            label="Description (optional)"
            class="community-input"
          />
          <button id="save-community" class="community-button" phx-disable-with="Creating...">Create</button>
          <.link navigate={~p"/communities"} class="ml-3 text-stone-600 hover:underline">cancel</.link>
        </.form>
      <% else %>
        <h1 class="mb-5 text-lg font-bold">Your communities</h1>
        <div id="communities" phx-update="stream" class="space-y-4">
          <p id="communities-empty" class="hidden text-stone-500 only:block">
            No communities yet.
            <.link navigate={~p"/communities/new"} class="underline">Create one</.link>
            to get started.
          </p>
          <article :for={{id, community} <- @streams.communities} id={id}>
            <.link navigate={~p"/communities/#{community}"} class="font-medium hover:underline">{community.name}</.link>
            <.link
              navigate={~p"/communities/#{community}/edit"}
              class="ml-3 text-xs text-stone-500 hover:underline"
            >settings</.link>
            <p class="mt-1 whitespace-pre-wrap break-words text-xs text-stone-500">
              {community.description}
            </p>
          </article>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
