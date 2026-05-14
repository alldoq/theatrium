defmodule AtriumWeb.TenantAdmin.SubsectionController do
  use AtriumWeb, :controller
  alias Atrium.Authorization
  alias Atrium.Authorization.{SectionRegistry, Subsection}

  def index(conn, %{"section_key" => section_key}) do
    prefix = conn.assigns.tenant_prefix
    section = SectionRegistry.get(section_key)

    unless section && section.supports_subsections do
      conn |> put_flash(:error, "This section does not support subsections.") |> redirect(to: ~p"/admin/users") |> halt()
    else
      subsections = Authorization.list_subsections(prefix, section_key)
      render(conn, :index, section: section, subsections: subsections, section_key: section_key)
    end
  end

  def new(conn, %{"section_key" => section_key}) do
    section = SectionRegistry.get(section_key)
    prefix = conn.assigns.tenant_prefix

    unless section && section.supports_subsections do
      conn |> put_flash(:error, "This section does not support subsections.") |> redirect(to: ~p"/admin/users") |> halt()
    else
      groups = Authorization.list_groups(prefix)
      render(conn, :new,
        section: section,
        section_key: section_key,
        groups: groups,
        changeset: Subsection.create_changeset(%Subsection{}, %{})
      )
    end
  end

  def create(conn, %{"section_key" => section_key, "subsection" => params}) do
    prefix = conn.assigns.tenant_prefix
    is_private = params["is_private"] == "true"
    group_id = params["restricted_group_id"]

    attrs =
      params
      |> Map.put("section_key", section_key)
      |> Map.put("is_private", is_private)

    case Authorization.create_subsection(prefix, attrs) do
      {:ok, ss} ->
        if is_private && group_id && group_id != "" do
          Enum.each([:view, :edit], fn cap ->
            Authorization.grant_subsection(
              prefix,
              section_key,
              ss.slug,
              {:group, group_id},
              cap,
              conn.assigns.current_user.id
            )
          end)
        end

        conn |> put_flash(:info, "Subsection created.") |> redirect(to: ~p"/admin/sections/#{section_key}/subsections")
      {:error, cs} ->
        section = SectionRegistry.get(section_key)
        groups = Authorization.list_groups(prefix)
        conn |> put_status(422) |> render(:new, section: section, section_key: section_key, groups: groups, changeset: cs)
    end
  end

  def delete(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    ss = Atrium.Repo.get!(Subsection, id, prefix: prefix)

    case Authorization.delete_subsection(prefix, ss) do
      {:ok, _} ->
        conn |> put_flash(:info, "Subsection deleted.") |> redirect(to: ~p"/admin/sections/#{section_key}/subsections")
      {:error, _} ->
        conn |> put_flash(:error, "Could not delete subsection.") |> redirect(to: ~p"/admin/sections/#{section_key}/subsections")
    end
  end
end
