defmodule ArcanumWeb.UserLive.Login do
  use ArcanumWeb, :live_view

  alias Arcanum.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} community>
      <div id="login-page" class="max-w-xl space-y-5">
        <h1 class="text-xl font-bold">Log in</h1>
        <p class="text-stone-600">
          <%= if @current_scope do %>
            You need to reauthenticate to perform sensitive actions on your account.
          <% else %>
            Don't have an account? <.link
              navigate={~p"/users/register"}
              class="text-blue-600 hover:underline"
              phx-no-format
            >Sign up</.link> for an account now.
          <% end %>
        </p>

        <.form
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
          class="space-y-4"
        >
          <.input
            id="login_form_magic_email"
            readonly={!!@current_scope}
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
            class="community-input"
          />
          <button id="login-with-email" class="community-button" phx-disable-with="Sending...">Log in with email</button>
        </.form>

        <div class="flex items-center gap-3 py-2 text-xs text-stone-500">
          <span class="h-px flex-1 bg-stone-200" />or<span class="h-px flex-1 bg-stone-200" />
        </div>

        <.form
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
          class="space-y-4"
        >
          <.input
            id="login_form_password_email"
            readonly={!!@current_scope}
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            class="community-input"
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            spellcheck="false"
            class="community-input"
          />
          <.input
            field={@form[:remember_me]}
            id="login-remember"
            type="checkbox"
            label="Stay logged in"
            class="size-4 cursor-pointer accent-blue-600"
          />
          <button id="login-submit" class="community-button" phx-disable-with="Logging in...">Log in</button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    result =
      if user = Accounts.get_user_by_email(email) do
        Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))
      else
        :ok
      end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    case result do
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Email delivery failed. Please try again.")}

      _ ->
        {:noreply, socket |> put_flash(:info, info) |> push_navigate(to: ~p"/users/log-in")}
    end
  end
end
