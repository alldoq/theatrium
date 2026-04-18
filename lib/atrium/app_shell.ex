defmodule Atrium.AppShell do
  @moduledoc """
  Assembles the per-request navigation structure: the subset of enabled
  sections the user is allowed to view, plus any viewable subsections.
  """
  alias Atrium.Authorization
  alias Atrium.Authorization.{Policy, SectionRegistry}

  @type nav_entry :: %{key: atom(), name: String.t(), icon: String.t(), children: [nav_child]}
  @type nav_child :: %{slug: String.t(), name: String.t()}

  @spec nav_for_user(Atrium.Tenants.Tenant.t(), Atrium.Accounts.User.t(), String.t()) :: [nav_entry]
  def nav_for_user(tenant, user, prefix) do
    enabled = MapSet.new(tenant.enabled_sections)

    SectionRegistry.all()
    |> Enum.filter(fn s -> MapSet.member?(enabled, to_string(s.key)) end)
    |> Enum.filter(fn s -> Policy.can?(prefix, user, :view, {:section, s.key}) end)
    |> Enum.map(fn s ->
      children =
        if s.supports_subsections do
          prefix
          |> Authorization.list_subsections(to_string(s.key))
          |> Enum.filter(&Policy.can?(prefix, user, :view, {:subsection, s.key, &1.slug}))
          |> Enum.map(&%{slug: &1.slug, name: &1.name})
        else
          []
        end

      %{key: s.key, name: s.name, icon: s.icon, children: children}
    end)
  end
end
