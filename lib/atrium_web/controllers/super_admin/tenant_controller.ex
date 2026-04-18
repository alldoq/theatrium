defmodule AtriumWeb.SuperAdmin.TenantController do
  use AtriumWeb, :controller

  alias Atrium.Tenants
  alias Atrium.Tenants.{Provisioner, Tenant}

  def index(conn, _params) do
    render(conn, :index, tenants: Tenants.list_tenants())
  end

  def new(conn, _params) do
    render(conn, :new, changeset: Tenants.change_tenant(%Tenant{}))
  end

  def create(conn, %{"tenant" => attrs}) do
    case Tenants.create_tenant_record(attrs) do
      {:ok, tenant} ->
        case Provisioner.provision(tenant, actor: {:super_admin, conn.assigns.super_admin.id}) do
          {:ok, provisioned} ->
            redirect(conn, to: ~p"/super/tenants/#{provisioned.id}")
          {:error, reason} ->
            _ = Tenants.delete_tenant(tenant)
            render(conn, :new, changeset: Tenants.change_tenant(%Tenant{}), error: "Provisioning failed: #{inspect(reason)}")
        end
      {:error, %Ecto.Changeset{} = cs} ->
        render(conn, :new, changeset: cs)
    end
  end

  def show(conn, %{"id" => id}) do
    render(conn, :show, tenant: Tenants.get_tenant!(id))
  end

  def edit(conn, %{"id" => id}) do
    tenant = Tenants.get_tenant!(id)
    sections = Atrium.Authorization.SectionRegistry.all()
    render(conn, :edit, tenant: tenant, changeset: Tenants.change_tenant(tenant), sections: sections)
  end

  def update(conn, %{"id" => id, "tenant" => attrs}) do
    tenant = Tenants.get_tenant!(id)
    attrs = Map.update(attrs, "enabled_sections", [], &Enum.reject(&1, fn v -> v == "" end))

    case Tenants.update_tenant(tenant, attrs) do
      {:ok, updated} ->
        {:ok, _} = Atrium.Audit.log_global("tenant.theme_updated", %{
          actor: {:super_admin, conn.assigns.super_admin.id},
          resource: {"Tenant", updated.id},
          changes: diff(tenant, updated)
        })

        redirect(conn, to: ~p"/super/tenants/#{updated.id}")

      {:error, cs} ->
        sections = Atrium.Authorization.SectionRegistry.all()
        render(conn, :edit, tenant: tenant, changeset: cs, sections: sections)
    end
  end

  def reseed_acls(conn, %{"id" => id}) do
    tenant = Tenants.get_tenant!(id)
    Tenants.ensure_default_acls(tenant)

    conn
    |> put_flash(:info, "Default ACLs re-seeded for #{tenant.name}.")
    |> redirect(to: ~p"/super/tenants/#{tenant.id}")
  end

  defp diff(old, new) do
    Map.new([:name, :theme, :enabled_sections, :allow_local_login], fn key ->
      {to_string(key), [Map.get(old, key), Map.get(new, key)]}
    end)
    |> Enum.filter(fn {_k, [a, b]} -> a != b end)
    |> Map.new()
  end
end
