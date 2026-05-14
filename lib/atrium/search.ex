defmodule Atrium.Search do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Documents.Document
  alias Atrium.Accounts.User
  alias Atrium.Tools.ToolLink
  alias Atrium.Home.Announcement
  alias Atrium.Learning.Course
  alias Atrium.Events.Event
  alias Atrium.Community.Post
  alias Atrium.Authorization.Policy

  @min_query_length 2

  @doc """
  Unified search across all readable surfaces. Returns
  `[%{type:, id:, title:, snippet:, path:, section:}]`,
  capped at `:limit` per type.
  """
  def global_search(prefix, user, query, opts \\ [])

  def global_search(_prefix, _user, query, _opts) when byte_size(query) < @min_query_length,
    do: []

  def global_search(prefix, user, query, opts) do
    limit = Keyword.get(opts, :limit, 5)

    [
      &search_announcements/4,
      &search_courses/4,
      &search_events/4,
      &search_community/4,
      &search_docs_global/4,
      &search_users_global/4,
      &search_tools_global/4
    ]
    |> Enum.flat_map(fn fun -> fun.(prefix, user, query, limit) end)
  end

  defp pattern(q), do: "%#{q}%"

  defp can_view_section?(prefix, user, section_key) do
    Policy.can?(prefix, user, :view, {:section, section_key})
  end

  defp truncate(nil, _), do: ""
  defp truncate(text, n) when is_binary(text) do
    plain = String.replace(text, ~r/<[^>]+>/, " ") |> String.replace(~r/\s+/, " ") |> String.trim()
    if String.length(plain) > n, do: String.slice(plain, 0, n) <> "…", else: plain
  end

  defp search_announcements(prefix, user, q, limit) do
    if can_view_section?(prefix, user, "home") do
      pat = pattern(q)
      now = DateTime.utc_now()

      from(a in Announcement,
        where: (is_nil(a.expires_at) or a.expires_at > ^now) and
                 (ilike(a.title, ^pat) or ilike(a.body_html, ^pat)),
        order_by: [desc: a.inserted_at],
        limit: ^limit
      )
      |> Repo.all(prefix: prefix)
      |> Enum.map(fn a ->
        %{type: :announcement, id: a.id, title: a.title,
          snippet: truncate(a.body_html, 140), path: "/home",
          section: "Announcements"}
      end)
    else
      []
    end
  end

  defp search_courses(prefix, user, q, limit) do
    if can_view_section?(prefix, user, "learning") do
      pat = pattern(q)

      from(c in Course,
        where: c.status == "published" and
                 (ilike(c.title, ^pat) or ilike(c.description, ^pat) or ilike(c.category, ^pat)),
        order_by: [desc: c.inserted_at],
        limit: ^limit
      )
      |> Repo.all(prefix: prefix)
      |> Enum.map(fn c ->
        %{type: :course, id: c.id, title: c.title,
          snippet: truncate(c.description, 140),
          path: "/learning/#{c.id}", section: "Learning"}
      end)
    else
      []
    end
  end

  defp search_events(prefix, user, q, limit) do
    if can_view_section?(prefix, user, "events") do
      pat = pattern(q)

      from(e in Event,
        where: ilike(e.title, ^pat) or ilike(e.description, ^pat) or ilike(e.location, ^pat),
        order_by: [desc: e.starts_at],
        limit: ^limit
      )
      |> Repo.all(prefix: prefix)
      |> Enum.map(fn e ->
        %{type: :event, id: e.id, title: e.title,
          snippet: truncate(e.description, 140),
          path: "/events/#{e.id}", section: "Events"}
      end)
    else
      []
    end
  end

  defp search_community(prefix, user, q, limit) do
    if can_view_section?(prefix, user, "community") do
      pat = pattern(q)

      from(p in Post,
        where: ilike(p.title, ^pat) or ilike(p.body, ^pat),
        order_by: [desc: p.inserted_at],
        limit: ^limit
      )
      |> Repo.all(prefix: prefix)
      |> Enum.map(fn p ->
        %{type: :community, id: p.id, title: p.title,
          snippet: truncate(p.body, 140),
          path: "/community/#{p.id}", section: "Community"}
      end)
    else
      []
    end
  end

  defp search_docs_global(prefix, user, q, limit) do
    sections = ~w(news hr docs compliance feedback departments helpdesk projects)
    allowed = Enum.filter(sections, &can_view_section?(prefix, user, &1))
    if allowed == [] do
      []
    else
      pat = pattern(q)

      from(d in Document,
        where: d.section_key in ^allowed and d.status == "approved" and
                 (ilike(d.title, ^pat) or ilike(d.body_html, ^pat)),
        order_by: [desc: d.inserted_at],
        limit: ^limit
      )
      |> Repo.all(prefix: prefix)
      |> Enum.map(fn d ->
        %{type: :document, id: d.id, title: d.title,
          snippet: truncate(d.body_html, 140),
          path: "/sections/#{d.section_key}/documents/#{d.id}",
          section: humanize_section(d.section_key)}
      end)
    end
  end

  defp search_users_global(prefix, user, q, limit) do
    if can_view_section?(prefix, user, "directory") do
      pat = pattern(q)

      from(u in User,
        where: u.status == "active" and
                 (ilike(u.name, ^pat) or ilike(u.email, ^pat) or
                    ilike(u.role, ^pat) or ilike(u.department, ^pat)),
        order_by: [asc: u.name],
        limit: ^limit
      )
      |> Repo.all(prefix: prefix)
      |> Enum.map(fn u ->
        meta = Enum.reject([u.role, u.department], &(is_nil(&1) or &1 == "")) |> Enum.join(" · ")
        %{type: :user, id: u.id, title: u.name,
          snippet: if(meta != "", do: meta <> " · ", else: "") <> (u.email || ""),
          path: "/directory/#{u.id}", section: "People"}
      end)
    else
      []
    end
  end

  defp search_tools_global(prefix, user, q, limit) do
    if can_view_section?(prefix, user, "tools") do
      pat = pattern(q)

      from(t in ToolLink,
        where: ilike(t.label, ^pat) or ilike(t.description, ^pat),
        order_by: [asc: t.label],
        limit: ^limit
      )
      |> Repo.all(prefix: prefix)
      |> Enum.map(fn t ->
        %{type: :tool, id: t.id, title: t.label,
          snippet: truncate(t.description, 140),
          path: "/tools", section: "Tools"}
      end)
    else
      []
    end
  end

  defp humanize_section("hr"), do: "HR & People"
  defp humanize_section("docs"), do: "Knowledge Base"
  defp humanize_section("news"), do: "News"
  defp humanize_section("compliance"), do: "Compliance"
  defp humanize_section("feedback"), do: "Feedback"
  defp humanize_section("departments"), do: "Departments"
  defp humanize_section("helpdesk"), do: "Helpdesk"
  defp humanize_section("projects"), do: "Projects"
  defp humanize_section(other), do: String.capitalize(other)

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
