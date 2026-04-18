defmodule AtriumWeb.Router do
  use AtriumWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AtriumWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :tenant do
    plug AtriumWeb.Plugs.TenantResolver
  end

  pipeline :super_admin_required do
    plug AtriumWeb.Plugs.RequireSuperAdmin
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Platform (super-admin) routes
  scope "/", AtriumWeb, host: "admin." do
    pipe_through [:browser]
    get "/super/login", SuperAdmin.SessionController, :new
    post "/super/login", SuperAdmin.SessionController, :create
    delete "/super/logout", SuperAdmin.SessionController, :delete

    scope "/super", as: :super_admin do
      pipe_through [:super_admin_required]
      get "/", SuperAdmin.DashboardController, :index
      resources "/tenants", SuperAdmin.TenantController, except: [:delete]
      resources "/tenants/:tenant_id/idps", SuperAdmin.TenantIdpController, except: [:show]
    end
  end

  # Health endpoint on platform host
  scope "/", AtriumWeb, host: "admin." do
    pipe_through [:api]
    get "/healthz", HealthController, :index
  end

  # Tenant-scoped routes (any other host)
  scope "/", AtriumWeb do
    pipe_through [:browser, :tenant]

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete

    get "/invitations/:token", InvitationController, :edit
    post "/invitations/:token", InvitationController, :update

    get "/password-reset/new", PasswordResetController, :new
    post "/password-reset", PasswordResetController, :create
    get "/password-reset/:token", PasswordResetController, :edit
    post "/password-reset/:token", PasswordResetController, :update

    get "/auth/oidc/callback", OidcController, :callback
    get "/auth/oidc/:id/start", OidcController, :start

    get "/auth/saml/:id/start", SamlController, :start
    post "/auth/saml/callback", SamlController, :consume

    scope "/" do
      pipe_through [AtriumWeb.Plugs.RequireUser]
      get "/", PageController, :home
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:atrium, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AtriumWeb.Telemetry
    end
  end
end
