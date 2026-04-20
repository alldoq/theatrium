defmodule AtriumWeb.TenantAdmin.SectionController do
  use AtriumWeb, :controller

  alias Atrium.{Accounts, Authorization}
  alias Atrium.Authorization.SectionRegistry

  @caps ["view", "edit", "approve"]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    sections = SectionRegistry.all()

    acl_counts =
      for section <- sections, into: %{} do
        acls = Authorization.list_section_acls(prefix, to_string(section.key))
        {to_string(section.key), length(acls)}
      end

    render(conn, :index, sections: sections, acl_counts: acl_counts)
  end

  def show(conn, %{"section_key" => key}) do
    prefix = conn.assigns.tenant_prefix

    case SectionRegistry.get(key) do
      nil ->
        conn |> put_flash(:error, "Unknown section.") |> redirect(to: ~p"/admin/sections")

      section ->
        acls = Authorization.list_section_acls(prefix, key)
        groups = Authorization.list_groups(prefix)
        users = Accounts.list_users(prefix)

        groups_by_id = Map.new(groups, &{&1.id, &1})
        users_by_id = Map.new(users, &{&1.id, &1})

        grouped =
          for cap <- @caps, into: %{} do
            rows =
              acls
              |> Enum.filter(&(&1.capability == cap))
              |> Enum.map(fn acl ->
                principal =
                  case acl.principal_type do
                    "group" -> {:group, Map.get(groups_by_id, acl.principal_id)}
                    "user" -> {:user, Map.get(users_by_id, acl.principal_id)}
                  end

                %{acl: acl, principal: principal}
              end)
              |> Enum.reject(fn %{principal: {_, p}} -> is_nil(p) end)

            {cap, rows}
          end

        render(conn, :show,
          section: section,
          section_key: key,
          capabilities: @caps,
          grants: grouped,
          groups: groups,
          users: users
        )
    end
  end

  def grant(conn, %{"section_key" => key, "principal_type" => ptype, "principal_id" => pid, "capability" => cap}) do
    prefix = conn.assigns.tenant_prefix
    actor = conn.assigns.current_user

    if SectionRegistry.get(key) && ptype in ["user", "group"] && cap in @caps && pid != "" do
      type_atom = String.to_existing_atom(ptype)
      Authorization.grant_section(prefix, key, {type_atom, pid}, cap, actor.id)
      conn |> put_flash(:info, "Permission granted.") |> redirect(to: ~p"/admin/sections/#{key}")
    else
      conn |> put_flash(:error, "Invalid input.") |> redirect(to: ~p"/admin/sections/#{key}")
    end
  end

  def revoke(conn, %{"section_key" => key, "principal_type" => ptype, "principal_id" => pid, "capability" => cap}) do
    prefix = conn.assigns.tenant_prefix

    if SectionRegistry.get(key) && ptype in ["user", "group"] && cap in @caps do
      type_atom = String.to_existing_atom(ptype)
      :ok = Authorization.revoke_section(prefix, key, {type_atom, pid}, cap)
      conn |> put_flash(:info, "Permission revoked.") |> redirect(to: ~p"/admin/sections/#{key}")
    else
      conn |> put_flash(:error, "Invalid input.") |> redirect(to: ~p"/admin/sections/#{key}")
    end
  end
end
