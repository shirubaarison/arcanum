defmodule ArcanumWeb.Router do
  use ArcanumWeb, :router

  import ArcanumWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ArcanumWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ArcanumWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  scope "/", ArcanumWeb do
    pipe_through :browser

    get "/", PageController, :redirect_root
  end

  # Other scopes may use custom stacks.
  # scope "/api", ArcanumWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:arcanum, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ArcanumWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", ArcanumWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{ArcanumWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/communities", CommunityLive.Index, :index
      live "/communities/new", CommunityLive.Index, :new
      live "/communities/:name/edit", CommunityLive.Edit, :edit
      live "/communities/:name/posts/new", CommunityLive.Show, :new_post
      live "/communities/:name/rooms/new", CommunityLive.Show, :new_room
      live "/communities/:community_name/rooms/:id", RoomLive.Show, :show
      live "/communities/:community_name/posts/:id", PostLive.Show, :show
      live "/communities/:name", CommunityLive.Show, :show
      live "/:username", UserLive.Profile, :show
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", ArcanumWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{ArcanumWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
