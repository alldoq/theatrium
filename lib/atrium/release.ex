defmodule Atrium.Release do
  @moduledoc """
  Release-time DB tasks.

  Runs global Ecto migrations against each configured repo, then iterates every
  row in the global `tenants` table and runs Triplex per-tenant migrations
  against that schema.

  Invoke via the generated `bin/migrate` script or:

      bin/atrium eval "Atrium.Release.migrate"
  """
  @app :atrium
  require Logger

  def migrate do
    load_app()
    Application.ensure_all_started(:triplex)

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn r ->
          Ecto.Migrator.run(r, :up, all: true)
          if r == Atrium.Repo, do: migrate_tenants()
        end)
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp migrate_tenants do
    for tenant <- Atrium.Tenants.list_tenants() do
      Logger.info("Migrating tenant schema: #{tenant.slug}")
      Triplex.migrate(tenant.slug)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
