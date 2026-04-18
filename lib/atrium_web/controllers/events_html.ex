defmodule AtriumWeb.EventsHTML do
  use AtriumWeb, :html

  embed_templates "events_html/*"

  def format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%d %b %Y, %H:%M")
  end

  def format_datetime(nil), do: ""

  def format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%d %b %Y")
  end

  def format_date(nil), do: ""

  def format_input_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%dT%H:%M")
  end

  def format_input_datetime(nil), do: ""
end
