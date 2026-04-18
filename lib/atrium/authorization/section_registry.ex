defmodule Atrium.Authorization.SectionRegistry do
  @moduledoc """
  The code-defined catalogue of the 14 canonical intranet sections, their
  default capabilities, and the default ACLs seeded on tenant provisioning.

  This is the single source of truth. Adding a 15th section is a code change
  plus (optionally) a default-ACLs-seed migration for existing tenants.
  """

  @capabilities [:view, :edit, :approve]

  @sections [
    %{
      key: :home,
      name: "Home",
      icon: "home",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :super_users, :edit}]
    },
    %{
      key: :news,
      name: "News & Announcements",
      icon: "megaphone",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :communications, :edit}, {:group, :communications, :approve}]
    },
    %{
      key: :directory,
      name: "Employee Directory",
      icon: "users",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :people_and_culture, :edit}]
    },
    %{
      key: :hr,
      name: "HR & People Services",
      icon: "heart",
      supports_subsections: true,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :people_and_culture, :edit}, {:group, :people_and_culture, :approve}]
    },
    %{
      key: :departments,
      name: "Departments & Teams",
      icon: "building",
      supports_subsections: true,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}]
    },
    %{
      key: :docs,
      name: "Documents & Knowledge Base",
      icon: "book",
      supports_subsections: true,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}]
    },
    %{
      key: :tools,
      name: "Tools & Applications",
      icon: "wrench",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :super_users, :edit}]
    },
    %{
      key: :projects,
      name: "Projects & Collaboration",
      icon: "kanban",
      supports_subsections: true,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}]
    },
    %{
      key: :helpdesk,
      name: "IT Support / Help Desk",
      icon: "life-buoy",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :it, :edit}, {:group, :it, :approve}]
    },
    %{
      key: :learning,
      name: "Learning & Development",
      icon: "graduation-cap",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :people_and_culture, :edit}]
    },
    %{
      key: :events,
      name: "Events & Calendar",
      icon: "calendar",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}]
    },
    %{
      key: :social,
      name: "Social / Community",
      icon: "chat",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :all_staff, :edit}]
    },
    %{
      key: :compliance,
      name: "Compliance & Policies",
      icon: "shield",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :compliance_officers, :edit}, {:group, :compliance_officers, :approve}]
    },
    %{
      key: :feedback,
      name: "Feedback & Surveys",
      icon: "message-circle",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :people_and_culture, :edit}, {:group, :people_and_culture, :approve}]
    }
  ]

  @section_keys Enum.map(@sections, & &1.key)

  def all, do: @sections
  def keys, do: @section_keys
  def capabilities, do: @capabilities

  def get(key) when is_atom(key) or is_binary(key) do
    k = if is_binary(key), do: String.to_existing_atom(key), else: key
    Enum.find(@sections, &(&1.key == k))
  rescue
    ArgumentError -> nil
  end

  def all_with_overrides do
    overrides = Atrium.Sections.list_customizations()

    Enum.map(@sections, fn section ->
      key_str = to_string(section.key)
      case Map.get(overrides, key_str) do
        nil ->
          section
        custom ->
          section
          |> Map.put(:name, custom.display_name || section.name)
          |> Map.put(:icon, custom.icon_name || section.icon)
      end
    end)
  end
end
