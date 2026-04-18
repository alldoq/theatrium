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

  pipeline :authenticated do
    plug AtriumWeb.Plugs.RequireUser
    plug AtriumWeb.Plugs.AssignNav
    plug :put_layout, html: {AtriumWeb.Layouts, :app}
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_tenant_admin do
    plug AtriumWeb.Plugs.RequireTenantAdmin
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

    get "/auth/link/confirm", LinkConfirmController, :new
    post "/auth/link/confirm", LinkConfirmController, :create

    get "/auth/oidc/callback", OidcController, :callback
    get "/auth/oidc/:id/start", OidcController, :start

    get "/auth/saml/:id/start", SamlController, :start
    post "/auth/saml/callback", SamlController, :consume

    get  "/forms/review/:token",          ExternalReviewController, :show
    post "/forms/review/:token/complete", ExternalReviewController, :complete

    scope "/" do
      pipe_through [:authenticated]
      get "/", PageController, :home
      get "/audit", AuditViewerController, :index
      get "/audit/export", AuditViewerController, :export

      scope "/admin", TenantAdmin, as: :tenant_admin do
        pipe_through [:require_tenant_admin]

        get  "/users",                    UserController, :index
        get  "/users/new",                UserController, :new
        post "/users",                    UserController, :create
        get  "/users/:id",                UserController, :show
        post "/users/:id/permissions",    UserController, :update_permissions
        post "/users/:id/toggle_admin",   UserController, :toggle_admin
        post "/users/:id/suspend",        UserController, :suspend
        post "/users/:id/restore",        UserController, :restore
      end

      get  "/sections/:section_key/documents",             DocumentController, :index
      get  "/sections/:section_key/documents/new",         DocumentController, :new
      post "/sections/:section_key/documents",             DocumentController, :create
      get  "/sections/:section_key/documents/:id",         DocumentController, :show
      get  "/sections/:section_key/documents/:id/edit",    DocumentController, :edit
      put  "/sections/:section_key/documents/:id",         DocumentController, :update
      post "/sections/:section_key/documents/:id/submit",  DocumentController, :submit
      post "/sections/:section_key/documents/:id/reject",  DocumentController, :reject
      post "/sections/:section_key/documents/:id/approve", DocumentController, :approve
      post "/sections/:section_key/documents/:id/archive", DocumentController, :archive

      get  "/sections/:section_key/forms",                                    FormController, :index
      get  "/sections/:section_key/forms/new",                                FormController, :new
      post "/sections/:section_key/forms",                                    FormController, :create
      get  "/sections/:section_key/forms/:id",                                FormController, :show
      get  "/sections/:section_key/forms/:id/edit",                           FormController, :edit
      put  "/sections/:section_key/forms/:id",                                FormController, :update
      post "/sections/:section_key/forms/:id/publish",                        FormController, :publish
      post "/sections/:section_key/forms/:id/archive",                        FormController, :archive
      post "/sections/:section_key/forms/:id/reopen",                         FormController, :reopen
      get  "/sections/:section_key/forms/:id/submit",                         FormController, :submit_form
      post "/sections/:section_key/forms/:id/submit",                         FormController, :create_submission
      get  "/sections/:section_key/forms/:id/submissions",                    FormController, :submissions_index
      get  "/sections/:section_key/forms/:id/submissions/:sid",               FormController, :show_submission
      post "/sections/:section_key/forms/:id/submissions/:sid/complete",      FormController, :complete_review
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
