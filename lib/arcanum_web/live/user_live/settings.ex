defmodule ArcanumWeb.UserLive.Settings do
  use ArcanumWeb, :live_view

  alias Arcanum.Accounts
  alias Arcanum.Accounts.Scope

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} community>
      <div id="account-settings" class="max-w-xl">
        <.back_link id="settings-back" fallback={~p"/communities"} />
        <h1 class="mt-3 text-xl font-bold">Account Settings</h1>
        <p class="mt-2 text-stone-600">Manage your username, email address and password.</p>

        <.form
          for={@username_form}
          id="username-form"
          phx-submit="update_username"
          phx-change="validate_username"
          class="mt-8 space-y-4"
        >
          <h2 class="font-bold">Username</h2>
          <.input
            field={@username_form[:username]}
            type="text"
            label="Username"
            autocomplete="nickname"
            minlength="3"
            maxlength="30"
            required
            class="community-input"
          />
          <button id="save-username" class="community-button" phx-disable-with="Saving...">Save username</button>
        </.form>

        <.form
          for={@email_form}
          id="email_form"
          phx-submit="update_email"
          phx-change="validate_email"
          class="mt-8 border-t border-stone-200 pt-6 space-y-4"
        >
          <h2 class="font-bold">Email address</h2>
          <.input
            field={@email_form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            class="community-input"
          />
          <p class="text-xs text-stone-500">We'll send a confirmation link to your new address.</p>
          <button id="change-email" class="community-button" phx-disable-with="Changing...">Change Email</button>
        </.form>

        <.form
          for={@password_form}
          id="password_form"
          action={~p"/users/update-password"}
          method="post"
          phx-change="validate_password"
          phx-submit="update_password"
          phx-trigger-action={@trigger_submit}
          class="mt-8 border-t border-stone-200 pt-6 space-y-4"
        >
          <h2 class="font-bold">Password</h2>
          <input
            name={@password_form[:email].name}
            type="hidden"
            id="hidden_user_email"
            spellcheck="false"
            value={@current_email}
          />
          <.input
            field={@password_form[:password]}
            type="password"
            label="New password"
            autocomplete="new-password"
            spellcheck="false"
            required
            class="community-input"
          />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            autocomplete="new-password"
            spellcheck="false"
            class="community-input"
          />
          <button id="save-password" class="community-button" phx-disable-with="Saving...">
            Save Password
          </button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, reason} ->
          ArcanumWeb.FailureLog.log("email change", reason)
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(
        :username_form,
        to_form(Accounts.change_user_username(socket.assigns.current_scope))
      )
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_username", %{"user" => attrs}, socket) do
    changeset =
      Accounts.change_user_username(socket.assigns.current_scope, attrs, validate_unique: false)

    {:noreply, assign(socket, :username_form, to_form(Map.put(changeset, :action, :validate)))}
  end

  def handle_event("update_username", %{"user" => attrs}, socket) do
    case Accounts.update_user_username(socket.assigns.current_scope, attrs) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_scope, Scope.for_user(user))
         |> assign(
           :username_form,
           to_form(Accounts.change_user_username(Scope.for_user(user)))
         )
         |> put_flash(:info, "Username updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :username_form, to_form(changeset))}
    end
  end

  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
