defmodule Atrium.Tenants.Seed do
  @moduledoc """
  Runs when a tenant is first provisioned. Creates the system groups and
  default section ACLs declared by the SectionRegistry.
  """
  alias Atrium.Authorization
  alias Atrium.Authorization.SectionRegistry

  @system_groups [
    %{slug: "all_staff", name: "All staff", description: "Every active user"},
    %{slug: "super_users", name: "Super users", description: "Tenant administrators"},
    %{slug: "people_and_culture", name: "People & Culture", description: "HR team"},
    %{slug: "it", name: "IT", description: "IT team"},
    %{slug: "finance", name: "Finance", description: "Finance team"},
    %{slug: "communications", name: "Communications", description: "Communications team"},
    %{slug: "compliance_officers", name: "Compliance Officers", description: "Compliance"}
  ]

  def run(prefix) do
    seed_groups(prefix)
    seed_default_acls(prefix)
    :ok
  end

  defp seed_groups(prefix) do
    Enum.each(@system_groups, fn attrs ->
      Authorization.create_group(prefix, Map.put(attrs, :kind, "system"))
    end)
  end

  defp seed_default_acls(prefix) do
    Enum.each(SectionRegistry.all(), fn section ->
      Enum.each(section.default_acls, fn
        {:group, group_slug, capability} ->
          case Authorization.get_group_by_slug(prefix, to_string(group_slug)) do
            nil -> :ok
            group ->
              Authorization.grant_section(prefix, to_string(section.key), {:group, group.id}, capability)
          end
      end)
    end)
  end
end
