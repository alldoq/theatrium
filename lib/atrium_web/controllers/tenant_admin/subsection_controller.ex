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

    unless section && section.supports_subsections do
      conn |> put_flash(:error, "This section does not support subsections.") |> redirect(to: ~p"/admin/users") |> halt()
    else
      render(conn, :new, section: section, section_key: section_key, changeset: Subsection.create_changeset(%Subsection{}, %{}))
    end
  end

  def create(conn, %{"section_key" => section_key, "subsection" => params}) do
    prefix = conn.assigns.tenant_prefix
    attrs = Map.merge(params, %{"section_key" => section_key})

    case Authorization.create_subsection(prefix, attrs) do
      {:ok, _} ->
        conn |> put_flash(:info, "Subsection created.") |> redirect(to: ~p"/admin/sections/#{section_key}/subsections")
      {:error, cs} ->
        section = SectionRegistry.get(section_key)
        conn |> put_status(422) |> render(:new, section: section, section_key: section_key, changeset: cs)
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
