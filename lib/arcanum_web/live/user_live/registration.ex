defmodule ArcanumWeb.UserLive.Registration do
  use ArcanumWeb, :live_view

  alias Arcanum.Accounts
  alias Arcanum.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} community>
      <div id="registration-page" class="max-w-xl">
        <h1 class="text-xl font-bold">Register for an account</h1>
        <p class="mt-2 text-stone-600">
          Already registered?
          <.link navigate={~p"/users/log-in"} class="text-blue-600 hover:underline">
            Log in
          </.link>
          to your account now.
        </p>

        <.form
          for={@form}
          id="registration_form"
          phx-submit="save"
          phx-change="validate"
          class="mt-6 space-y-4"
        >
          <.input
            field={@form[:username]}
            type="text"
            label="Username"
            autocomplete="nickname"
            minlength="3"
            maxlength="30"
            spellcheck="false"
            required
            class="community-input"
          />
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="email"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
            class="community-input"
          />

          <p class="text-xs text-stone-500">
            We'll email you a link to confirm your account.
          </p>
          <button id="create-account" phx-disable-with="Creating account..." class="community-button">
            Create an account
          </button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: ArcanumWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{}, %{}, validate_unique: false)

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        delivery =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        socket =
          case delivery do
            {:ok, _} ->
              put_flash(
                socket,
                :info,
                "An email was sent to #{user.email}, please access it to confirm your account."
              )

            {:error, _} ->
              put_flash(
                socket,
                :error,
                "Account created, but email delivery failed. Request a new link from the login page."
              )
          end

        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
