defmodule Atrium.Documents.Format do
  def bytes(n) when is_integer(n) and n < 1_024, do: "#{n} B"
  def bytes(n) when is_integer(n) and n < 1_048_576, do: "#{Float.round(n / 1_024, 1)} KB"
  def bytes(n) when is_integer(n) and n < 1_073_741_824, do: "#{Float.round(n / 1_048_576, 1)} MB"
  def bytes(n) when is_integer(n), do: "#{Float.round(n / 1_073_741_824, 2)} GB"
  def bytes(_), do: "?"
end
