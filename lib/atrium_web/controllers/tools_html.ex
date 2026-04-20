defmodule AtriumWeb.ToolsHTML do
  use AtriumWeb, :html
  embed_templates "tools_html/*"

  def format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  def format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
