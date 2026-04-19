defmodule AtriumWeb.HomeHTML do
  use AtriumWeb, :html
  embed_templates "home_html/*"

  defp humanize_action(action) do
    case action do
      "document.created" -> "created a document"
      "document.updated" -> "updated a document"
      "document.approved" -> "approved a document"
      "document.archived" -> "archived a document"
      "project.created" -> "created a project"
      "project.updated" -> "updated a project"
      "form.created" -> "created a form"
      "form.published" -> "published a form"
      _ -> action |> String.replace(".", " ") |> String.replace("_", " ")
    end
  end
end
