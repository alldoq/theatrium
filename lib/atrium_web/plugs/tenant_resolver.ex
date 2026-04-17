defmodule AtriumWeb.Plugs.TenantResolver do
  @moduledoc """
  Resolves the tenant from the request host's leading subdomain, loads the
  tenant record, rejects suspended/missing tenants, and sets the Triplex
  prefix for the request.

  This plug MUST NOT be mounted on platform-admin routes; those routes run
  under a separate pipeline that never sets a tenant prefix.
  """
  import Plug.Conn
  alias Atrium.Tenants

  @platform_subdomains ~w(admin www)

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, slug} <- extract_slug(conn.host),
         {:ok, tenant} <- fetch_tenant(slug) do
      handle_tenant(conn, tenant)
    else
      :platform_host ->
        conn
        |> send_resp(400, "Platform host cannot serve tenant routes")
        |> halt()

      :no_subdomain ->
        conn
        |> send_resp(400, "Missing tenant subdomain")
        |> halt()

      {:error, :not_found} ->
        conn
        |> send_resp(404, "Unknown tenant")
        |> halt()
    end
  end

  defp fetch_tenant(slug) do
    case Tenants.get_tenant_by_slug(slug) do
      %Tenants.Tenant{} = t -> {:ok, t}
      nil -> {:error, :not_found}
    end
  end

  defp extract_slug(host) do
    case String.split(host, ".", parts: 2) do
      [sub, _rest] when sub in @platform_subdomains -> :platform_host
      [sub, _rest] when sub != "" -> {:ok, sub}
      _ -> :no_subdomain
    end
  end

  defp handle_tenant(conn, %{status: "active"} = tenant) do
    conn
    |> assign(:tenant, tenant)
    |> assign(:tenant_prefix, Triplex.to_prefix(tenant.slug))
  end

  defp handle_tenant(conn, %{status: "suspended"}) do
    conn |> send_resp(503, "Tenant suspended") |> halt()
  end

  defp handle_tenant(conn, %{status: "provisioning"}) do
    conn |> send_resp(503, "Tenant provisioning") |> halt()
  end

  defp handle_tenant(conn, %{status: status}) do
    conn
    |> send_resp(503, "Tenant unavailable (status: #{status})")
    |> halt()
  end
end
