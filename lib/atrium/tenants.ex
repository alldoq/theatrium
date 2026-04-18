defmodule Atrium.Tenants do
  @moduledoc """
  Public API for tenant records in the public schema.

  Provisioning (schema creation + seeding) lives in `Atrium.Tenants.Provisioner`.
  """
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Tenants.Tenant

  @spec create_tenant_record(map()) :: {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()}
  def create_tenant_record(attrs) do
    %Tenant{}
    |> Tenant.create_changeset(attrs)
    |> Repo.insert()
  end

  @spec get_tenant_by_slug(String.t()) :: Tenant.t() | nil
  def get_tenant_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Tenant, slug: slug)
  end

  @spec get_tenant!(Ecto.UUID.t()) :: Tenant.t()
  def get_tenant!(id), do: Repo.get!(Tenant, id)

  @spec list_tenants() :: [Tenant.t()]
  def list_tenants, do: Repo.all(from t in Tenant, order_by: [asc: t.slug])

  @spec list_active_tenants() :: [Tenant.t()]
  def list_active_tenants do
    Repo.all(from t in Tenant, where: t.status == "active", order_by: [asc: t.slug])
  end

  @spec update_tenant(Tenant.t(), map()) :: {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()}
  def update_tenant(tenant, attrs) do
    case tenant |> Tenant.update_changeset(attrs) |> Repo.update() do
      {:ok, updated} = ok ->
        prefix = "tenant_#{updated.slug}"
        if Triplex.exists?(prefix), do: Atrium.Tenants.Seed.ensure_default_acls(prefix)
        ok
      err -> err
    end
  end

  @spec ensure_default_acls(Tenant.t()) :: :ok
  def ensure_default_acls(%Tenant{slug: slug}) do
    Atrium.Tenants.Seed.ensure_default_acls("tenant_#{slug}")
  end

  @spec update_status(Tenant.t(), String.t()) :: {:ok, Tenant.t()} | {:error, term()}
  def update_status(tenant, status) do
    tenant
    |> Tenant.status_changeset(status)
    |> Repo.update()
  end

  @spec change_tenant(Tenant.t(), map()) :: Ecto.Changeset.t()
  def change_tenant(tenant, attrs \\ %{}), do: Tenant.update_changeset(tenant, attrs)

  @spec delete_tenant(Tenant.t()) :: {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()}
  def delete_tenant(%Tenant{} = tenant), do: Repo.delete(tenant)
end
