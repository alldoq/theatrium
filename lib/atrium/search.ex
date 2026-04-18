defmodule Atrium.Search do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Documents.Document
  alias Atrium.Accounts.User
  alias Atrium.Tools.ToolLink

  @min_query_length 2

  @spec search_documents(String.t(), String.t(), [String.t()]) :: [Document.t()]
  def search_documents(_prefix, query, _section_keys)
      when byte_size(query) < @min_query_length,
      do: []

  def search_documents(_prefix, _query, []), do: []

  def search_documents(prefix, query, section_keys) do
    pattern = "%#{query}%"

    from(d in Document,
      where: d.section_key in ^section_keys,
      where: d.status == "approved",
      where: ilike(d.title, ^pattern) or ilike(d.body_html, ^pattern),
      order_by: [desc: d.inserted_at]
    )
    |> Repo.all(prefix: prefix)
  end

  @spec search_users(String.t(), String.t()) :: [User.t()]
  def search_users(_prefix, query)
      when byte_size(query) < @min_query_length,
      do: []

  def search_users(prefix, query) do
    pattern = "%#{query}%"

    from(u in User,
      where: u.status == "active",
      where:
        ilike(u.name, ^pattern) or
          ilike(u.email, ^pattern) or
          ilike(u.role, ^pattern) or
          ilike(u.department, ^pattern),
      order_by: [desc: u.inserted_at]
    )
    |> Repo.all(prefix: prefix)
  end

  @spec search_tools(String.t(), String.t()) :: [ToolLink.t()]
  def search_tools(_prefix, query)
      when byte_size(query) < @min_query_length,
      do: []

  def search_tools(prefix, query) do
    pattern = "%#{query}%"

    from(t in ToolLink,
      where: ilike(t.label, ^pattern) or ilike(t.description, ^pattern),
      order_by: [desc: t.inserted_at]
    )
    |> Repo.all(prefix: prefix)
  end
end
