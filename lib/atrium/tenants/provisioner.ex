defmodule Atrium.Tenants.Provisioner do
  @moduledoc """
  Creates and tears down per-tenant schemas via Triplex, and keeps the public
  tenant record in sync. Always writes to `audit_events_global`.
  """
  alias Atrium.{Audit, Repo, Tenants}
  alias Atrium.Tenants.Tenant

  @spec provision(Tenant.t(), keyword()) :: {:ok, Tenant.t()} | {:error, term()}
  def provision(%Tenant{} = tenant, opts \\ []) do
    actor = Keyword.get(opts, :actor, :system)

    case Triplex.create(tenant.slug) do
      {:ok, _schema} ->
        prefix = Triplex.to_prefix(tenant.slug)
        :ok = Atrium.Tenants.Seed.run(prefix)

        with {:ok, updated} <- Tenants.update_status(tenant, "active"),
             {:ok, _} <- Audit.log_global("tenant.created", %{
               actor: actor,
               resource: {"Tenant", tenant.id},
               changes: %{"slug" => [nil, tenant.slug], "status" => ["provisioning", "active"]}
             }) do
          {:ok, updated}
        else
          {:error, reason} ->
            _ = Triplex.drop(tenant.slug)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec suspend(Tenant.t(), keyword()) :: {:ok, Tenant.t()} | {:error, term()}
  def suspend(tenant, opts \\ [])

  def suspend(%Tenant{status: "active"} = tenant, opts) do
    actor = Keyword.get(opts, :actor, :system)

    with {:ok, updated} <- Tenants.update_status(tenant, "suspended"),
         {:ok, _} <- Audit.log_global("tenant.suspended", %{
           actor: actor,
           resource: {"Tenant", tenant.id},
           changes: %{"status" => ["active", "suspended"]}
         }) do
      {:ok, updated}
    end
  end

  def suspend(%Tenant{} = tenant, _), do: {:error, {:invalid_status_transition, tenant.status, "suspended"}}

  @spec resume(Tenant.t(), keyword()) :: {:ok, Tenant.t()} | {:error, term()}
  def resume(tenant, opts \\ [])

  def resume(%Tenant{status: "suspended"} = tenant, opts) do
    actor = Keyword.get(opts, :actor, :system)

    with {:ok, updated} <- Tenants.update_status(tenant, "active"),
         {:ok, _} <- Audit.log_global("tenant.resumed", %{
           actor: actor,
           resource: {"Tenant", tenant.id},
           changes: %{"status" => ["suspended", "active"]}
         }) do
      {:ok, updated}
    end
  end

  def resume(%Tenant{} = tenant, _), do: {:error, {:invalid_status_transition, tenant.status, "active"}}

  @spec destroy(Tenant.t()) :: :ok | {:error, term()}
  def destroy(%Tenant{} = tenant) do
    # If schema doesn't exist, proceed to delete the record anyway
    _ = Triplex.drop(tenant.slug)
    case Repo.delete(tenant) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
