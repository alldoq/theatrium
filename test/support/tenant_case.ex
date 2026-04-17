defmodule Atrium.TenantCase do
  @moduledoc """
  Test case for tests that run inside a tenant schema.

  Usage:

      defmodule Atrium.Accounts.UsersTest do
        use Atrium.TenantCase
        # `tenant` and `tenant_prefix` are available via the setup context
      end

  Creates a unique tenant per test module (not per test — expensive), runs
  Triplex migrations in the tenant schema, and tears the schema down in on_exit.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Atrium.DataCase, only: [errors_on: 1]
    end
  end

  setup_all do
    # Triplex DDL (CREATE SCHEMA) and Ecto migrations spawn Tasks that need
    # unconstrained DB connections. Switch to :auto mode briefly for provisioning
    # so all processes can access the pool freely, then restore :manual for tests.
    Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :auto)

    slug = "test_" <> (:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower))
    {:ok, tenant} = Atrium.Tenants.create_tenant_record(%{slug: slug, name: "Test #{slug}"})
    {:ok, tenant} = Atrium.Tenants.Provisioner.provision(tenant)

    Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :manual)

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :auto)
      _ = Triplex.drop(slug)

      t = Atrium.Tenants.get_tenant_by_slug(slug)
      if t, do: Atrium.Repo.delete(t)

      Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :manual)
    end)

    {:ok, tenant: tenant, tenant_prefix: Triplex.to_prefix(slug)}
  end

  setup %{tenant: tenant} = ctx do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Atrium.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, {:shared, self()})
    {:ok, Map.put(ctx, :tenant_prefix, Triplex.to_prefix(tenant.slug))}
  end
end
