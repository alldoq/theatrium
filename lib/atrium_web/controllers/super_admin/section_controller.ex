defmodule AtriumWeb.SuperAdmin.SectionController do
  use AtriumWeb, :controller

  alias Atrium.Authorization.SectionRegistry
  alias Atrium.Sections

  def index(conn, _params) do
    sections = SectionRegistry.all_with_overrides()
    render(conn, :index, sections: sections)
  end

  def edit(conn, %{"key" => key}) do
    section = fetch_section!(key)
    customization = Sections.get_customization(key)
    render(conn, :edit, section: section, customization: customization)
  end

  def update(conn, %{"key" => key, "section" => params}) do
    section = fetch_section!(key)
    display_name = normalize_empty(params["display_name"])
    icon_name = normalize_empty(params["icon_name"])

    case Sections.upsert_customization(key, %{display_name: display_name, icon_name: icon_name}) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Section updated.")
        |> redirect(to: ~p"/super/sections")

      {:error, _changeset} ->
        customization = Sections.get_customization(key)
        conn
        |> put_flash(:error, "Failed to save section.")
        |> render(:edit, section: section, customization: customization)
    end
  end

  defp fetch_section!(key) do
    case SectionRegistry.get(key) do
      nil -> raise Ecto.NoResultsError, queryable: Atrium.Sections.SectionCustomization
      section -> section
    end
  end

  defp normalize_empty(""), do: nil
  defp normalize_empty(val), do: val
end
