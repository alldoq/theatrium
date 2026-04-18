defmodule AtriumWeb.SuperAdmin.TenantIdpController do
  use AtriumWeb, :controller
  alias Atrium.Tenants
  alias Atrium.Accounts.{Idp, IdpConfiguration}

  def index(conn, %{"tenant_id" => tid}) do
    tenant = Tenants.get_tenant!(tid)
    prefix = Triplex.to_prefix(tenant.slug)
    render(conn, :index, tenant: tenant, idps: Idp.list_idps(prefix))
  end

  def new(conn, %{"tenant_id" => tid}) do
    tenant = Tenants.get_tenant!(tid)
    changeset = IdpConfiguration.create_changeset(%IdpConfiguration{}, %{})
    render(conn, :new, tenant: tenant, changeset: changeset)
  end

  def create(conn, %{"tenant_id" => tid, "idp" => attrs}) do
    tenant = Tenants.get_tenant!(tid)
    prefix = Triplex.to_prefix(tenant.slug)

    case Idp.create_idp(prefix, attrs) do
      {:ok, _idp} -> redirect(conn, to: ~p"/super/tenants/#{tid}/idps")
      {:error, cs} -> render(conn, :new, tenant: tenant, changeset: cs)
    end
  end

  def edit(conn, %{"tenant_id" => tid, "id" => id}) do
    tenant = Tenants.get_tenant!(tid)
    prefix = Triplex.to_prefix(tenant.slug)
    idp = Idp.get_idp!(prefix, id)
    changeset = IdpConfiguration.update_changeset(idp, %{})
    render(conn, :edit, tenant: tenant, idp: idp, changeset: changeset)
  end

  def update(conn, %{"tenant_id" => tid, "id" => id, "idp" => attrs}) do
    tenant = Tenants.get_tenant!(tid)
    prefix = Triplex.to_prefix(tenant.slug)
    idp = Idp.get_idp!(prefix, id)

    case Idp.update_idp(prefix, idp, attrs) do
      {:ok, _} -> redirect(conn, to: ~p"/super/tenants/#{tid}/idps")
      {:error, cs} -> render(conn, :edit, tenant: tenant, idp: idp, changeset: cs)
    end
  end

  def delete(conn, %{"tenant_id" => tid, "id" => id}) do
    tenant = Tenants.get_tenant!(tid)
    prefix = Triplex.to_prefix(tenant.slug)
    idp = Idp.get_idp!(prefix, id)
    {:ok, _} = Idp.delete_idp(prefix, idp)
    redirect(conn, to: ~p"/super/tenants/#{tid}/idps")
  end
end
