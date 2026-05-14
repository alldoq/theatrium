defmodule AtriumWeb.SearchController do
  use AtriumWeb, :controller

  alias Atrium.Search
  alias Atrium.Authorization.Policy

  @min_query_length 2

  def index(conn, params) do
    query = params["q"] || ""
    prefix = conn.assigns.tenant_prefix
    user   = conn.assigns.current_user
    nav    = conn.assigns.nav

    {documents, users, tools} =
      if String.length(query) >= @min_query_length do
        viewable_section_keys = Enum.map(nav, &to_string(&1.key))

        docs =
          Search.search_documents(prefix, query, viewable_section_keys)

        found_users =
          if Policy.can?(prefix, user, :view, {:section, "directory"}) do
            Search.search_users(prefix, query)
          else
            []
          end

        found_tools =
          if Policy.can?(prefix, user, :view, {:section, "tools"}) do
            Search.search_tools(prefix, query)
          else
            []
          end

        {docs, found_users, found_tools}
      else
        {[], [], []}
      end

    render(conn, :index,
      query: query,
      documents: documents,
      users: users,
      tools: tools
    )
  end

  def suggest(conn, params) do
    query = String.trim(params["q"] || "")
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    results =
      if String.length(query) >= @min_query_length do
        Atrium.Search.global_search(prefix, user, query, limit: 4)
      else
        []
      end

    json(conn, %{query: query, results: Enum.map(results, &serialize/1)})
  end

  defp serialize(%{type: t, id: id, title: title, snippet: snippet, path: path, section: section}) do
    %{type: t, id: id, title: title, snippet: snippet, path: path, section: section}
  end
end
