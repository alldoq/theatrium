defmodule Mix.Tasks.Atrium.ProvisionTenant do
  @shortdoc "Provision a new tenant: create public record and tenant schema"
  @moduledoc """
  Usage:

      mix atrium.provision_tenant --slug mcl --name "MCL"
  """
  use Mix.Task

  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [slug: :string, name: :string])

    slug = Keyword.get(opts, :slug) || Mix.raise("--slug is required")
    name = Keyword.get(opts, :name) || Mix.raise("--name is required")

    case Tenants.create_tenant_record(%{slug: slug, name: name}) do
      {:ok, tenant} ->
        case Provisioner.provision(tenant) do
          {:ok, provisioned} ->
            Mix.shell().info("Provisioned tenant #{provisioned.slug} (#{provisioned.id})")

          {:error, reason} ->
            _ = Tenants.delete_tenant(tenant)
            Mix.raise("Failed to provision: #{inspect(reason)}")
        end

      {:error, changeset} ->
        Mix.raise("Invalid tenant attrs: #{inspect(errors(changeset))}")
    end
  end

  defp errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
  end
end
