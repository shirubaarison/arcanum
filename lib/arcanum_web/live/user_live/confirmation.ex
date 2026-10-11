defmodule ArcanumWeb.UserLive.Confirmation do
  use ArcanumWeb, :live_view

  alias Arcanum.Accounts
  alias Arcanum.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} community>
      <div id="confirmation-page" class="max-w-xl">
        <h1 class="text-xl font-bold">Welcome {@user.username}</h1>
        <p class="mt-2 text-stone-600">
          {if(@user.confirmed_at,
            do: "Log in using your email link.",
            else: "Choose a password to activate your account."
          )}
        </p>

        <.form
          :if={!@user.confirmed_at}
          for={@form}
          id="confirmation_form"
          method="post"
          phx-mounted={JS.focus_first()}
          phx-submit="submit"
          action={~p"/users/log-in?_action=confirmed"}
          phx-trigger-action={@trigger_submit}
          class="mt-6 space-y-4"
        >
          <.input type="hidden" name="user[token]" id="activation-token" value={@token} />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="new-password"
            minlength="12"
            required
            class="community-input"
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm password"
            autocomplete="new-password"
            required
            class="community-input"
          />
          <p class="text-xs text-stone-500">Use at least 12 characters.</p>
          <.input
            name="user[remember_me]"
            id="activate-remember"
            type="checkbox"
            label="Stay logged in"
            checked={@remember_me}
            class="size-4 cursor-pointer accent-blue-600"
          />
          <button id="activate-submit" phx-disable-with="Confirming..." class="community-button">Activate account</button>
        </.form>

        <.form
          :if={@user.confirmed_at}
          for={@form}
          id="login_form"
          phx-submit="submit"
          phx-mounted={JS.focus_first()}
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_submit}
          class="mt-6 space-y-4"
        >
          <.input type="hidden" name="user[token]" id="login-link-token" value={@token} />
          <.input
            :if={!@current_scope}
            name="user[remember_me]"
            id="confirm-login-remember"
            type="checkbox"
            label="Stay logged in"
            checked={@remember_me}
            class="size-4 cursor-pointer accent-blue-600"
          />
          <button id="confirm-login" phx-disable-with="Logging in..." class="community-button">Log in</button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form =
        if user.confirmed_at do
          to_form(%{"token" => token}, as: "user")
        else
          to_form(User.activation_changeset(user, %{}, hash_password: false))
        end

      {:ok,
       assign(socket,
         user: user,
         token: token,
         form: form,
         remember_me: false,
         trigger_submit: false
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Magic link is invalid or it has expired.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    socket = assign(socket, :remember_me, params["remember_me"] in [true, "true"])

    if socket.assigns.user.confirmed_at do
      {:noreply, assign(socket, trigger_submit: true)}
    else
      changeset = User.activation_changeset(socket.assigns.user, params, hash_password: false)

      if changeset.valid? do
        {:noreply, assign(socket, form: to_form(changeset), trigger_submit: true)}
      else
        {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :insert)))}
      end
    end
  end
end
