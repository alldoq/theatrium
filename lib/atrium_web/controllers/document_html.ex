defmodule AtriumWeb.DocumentHTML do
  use AtriumWeb, :html

  embed_templates "document_html/*"

  def status_badge_class("draft"),     do: "bg-slate-100 text-slate-700"
  def status_badge_class("in_review"), do: "bg-yellow-100 text-yellow-700"
  def status_badge_class("approved"),  do: "bg-green-100 text-green-700"
  def status_badge_class("archived"),  do: "bg-slate-200 text-slate-500"
  def status_badge_class(_),           do: "bg-slate-100 text-slate-700"

  def document_icon_label(%{kind: "file"} = doc) do
    case Map.get(doc, :mime_type) do
      "application/pdf" -> "pdf"
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" -> "doc"
      "application/msword" -> "doc"
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" -> "xls"
      "application/vnd.ms-excel" -> "xls"
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" -> "ppt"
      "application/vnd.ms-powerpoint" -> "ppt"
      "application/vnd.oasis.opendocument.text" -> "doc"
      "text/plain" -> "txt"
      "image/" <> _ -> "img"
      _ -> "file"
    end
  end

  def document_icon_label(_), do: "doc"
end
