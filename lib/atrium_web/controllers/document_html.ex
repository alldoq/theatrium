defmodule AtriumWeb.DocumentHTML do
  use AtriumWeb, :html

  embed_templates "document_html/*"

  def status_badge_class("draft"),     do: "bg-slate-100 text-slate-700"
  def status_badge_class("in_review"), do: "bg-yellow-100 text-yellow-700"
  def status_badge_class("approved"),  do: "bg-green-100 text-green-700"
  def status_badge_class("archived"),  do: "bg-slate-200 text-slate-500"
  def status_badge_class(_),           do: "bg-slate-100 text-slate-700"
end
