defmodule LuxpkgsWeb.Router do
  alias LuxpkgsWeb.Pipelines
  use LuxpkgsWeb, :router

  import LuxpkgsWeb.UserAuth

  @csp "#{if Mix.env() == :dev, do: "http://127.0.0.1:4007"}"

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LuxpkgsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => @csp}
    plug :fetch_current_scope_for_user
    plug LuxpkgsWeb.Plugs.RequireTotp
  end

  pipeline :totp_verification do
    plug LuxpkgsWeb.Plugs.RateLimiter, tier: :totp
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug Pipelines.ApiPipeline
    plug :fetch_current_api_token_for_user
    plug OpenApiSpex.Plug.PutApiSpec, module: LuxpkgsWeb.ApiSpec
    plug LuxpkgsWeb.Plugs.RateLimiter, tier: :general
  end

  scope "/", LuxpkgsWeb do
    pipe_through :browser

    live_session :default, on_mount: [{LuxpkgsWeb.UserAuth, :mount_current_scope}] do
      live "/", PageLive
      live "/packages", PackageLive.Index, :index
      live "/package/:name", PackageLive.Show, :show
      live "/users/:username", UserLive.Profile, :show
      live "/donate", DonateLive
      live "/login", UserLive.Login, :new
      live "/provide-email", UserLive.ProvideEmail, :new
      live "/setup-totp", UserLive.SetupTotp, :setup

      post "/complete-signup", UserOauth, :complete_signup
    end
  end

  scope "/", LuxpkgsWeb do
    pipe_through [:browser, :totp_verification]

    post "/setup-totp/complete", UserOauth, :complete_totp_setup
  end

  # Authentication routes
  scope "/", LuxpkgsWeb, on_mount: [{LuxpkgsWeb.UserAuth, :mount_current_scope}] do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated, on_mount: [{LuxpkgsWeb.UserAuth, :mount_current_scope}] do
      live "/settings", UserLive.Settings, :edit
      live "/keys", UserLive.Keys, :index
    end

    delete "/logout", UserAuthController, :log_out_user
  end

  scope "/admin", LuxpkgsWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :admin,
      on_mount: [
        {LuxpkgsWeb.UserAuth, :mount_current_scope},
        {LuxpkgsWeb.AdminAuth, :require_admin}
      ] do
      live "/", AdminLive.Dashboard, :index
    end
  end

  scope "/admin", LuxpkgsWeb do
    pipe_through [:browser, :totp_verification, :require_authenticated_user]

    get "/verify", AdminTotpController, :new
    post "/verify", AdminTotpController, :create
  end

  scope "/auth", LuxpkgsWeb do
    pipe_through :browser

    get "/:provider", UserOauth, :request
    get "/:provider/callback", UserOauth, :callback
  end

  scope "/", LuxpkgsWeb do
    pipe_through :api

    get "/api/tool_version", LuaRocksApiController, :tool_version
    get "/api/1/:key/status", LuaRocksApiController, :status
    get "/api/1/:key/check_rockspec", LuaRocksApiController, :check_rockspec
    post "/api/1/:key/upload", LuaRocksApiController, :upload
    post "/api/1/:key/upload_rock/:version_id", LuaRocksApiController, :upload_rock
  end

  scope "/api", LuxpkgsWeb do
    pipe_through :api

    resources "/packages", PackageController,
      except: [:new, :edit, :update, :delete],
      param: "name"

    resources "/releases", ReleaseController, except: [:new, :edit, :update, :delete]
    post "/revoke", RevokedKeyController, :create
    get "/download/:name", PackageController, :download
    get "/download/:name/:version", PackageController, :download_version
  end

  scope "/api" do
    pipe_through :api

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end

  scope "/" do
    pipe_through :browser

    get "/swaggerui", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:luxpkgs, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LuxpkgsWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
