defmodule AtriumWeb.SuperAdmin.SectionController do
  use AtriumWeb, :controller

  alias Atrium.Authorization.SectionRegistry
  alias Atrium.Sections

  def index(conn, _params) do
    sections = SectionRegistry.all_with_overrides()
    render(conn, :index, sections: sections)
  end

  def edit(conn, %{"key" => key}) do
    case fetch_section(key) do
      {:ok, section} ->
        customization = Sections.get_customization(key)
        render(conn, :edit, section: section, customization: customization)
      :error ->
        conn |> put_status(:not_found) |> put_view(AtriumWeb.ErrorHTML) |> render(:"404") |> halt()
    end
  end

  def update(conn, %{"key" => key, "section" => params}) do
    case fetch_section(key) do
      {:ok, section} ->
        display_name = normalize_empty(params["display_name"])
        icon_name = normalize_empty(params["icon_name"])

        if icon_name != nil && !AtriumWeb.Heroicons.valid_name?(icon_name) do
          customization = %{display_name: display_name, icon_name: icon_name}
          conn
          |> put_flash(:error, "Invalid icon name.")
          |> render(:edit, section: section, customization: customization)
        else
          case Sections.upsert_customization(key, %{display_name: display_name, icon_name: icon_name}) do
            {:ok, _} ->
              conn
              |> put_flash(:info, "Section updated.")
              |> redirect(to: ~p"/super/sections")

            {:error, _changeset} ->
              customization = %{display_name: display_name, icon_name: icon_name}
              conn
              |> put_flash(:error, "Failed to save section.")
              |> render(:edit, section: section, customization: customization)
          end
        end
      :error ->
        conn |> put_status(:not_found) |> put_view(AtriumWeb.ErrorHTML) |> render(:"404") |> halt()
    end
  end

  defp fetch_section(key) do
    case SectionRegistry.get(key) do
      nil -> :error
      section -> {:ok, section}
    end
  end

  defp normalize_empty(""), do: nil
  defp normalize_empty(val), do: val
end
