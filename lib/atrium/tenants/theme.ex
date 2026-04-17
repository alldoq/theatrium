defmodule Atrium.Tenants.Theme do
  @moduledoc false
  @type t :: %__MODULE__{
          primary: String.t(),
          secondary: String.t(),
          accent: String.t(),
          font: String.t(),
          logo_url: String.t() | nil
        }

  defstruct primary: "#0F172A",
            secondary: "#64748B",
            accent: "#2563EB",
            font: "Inter, system-ui, sans-serif",
            logo_url: nil

  @spec default() :: t()
  def default, do: %__MODULE__{}

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    keys = ~w(primary secondary accent font logo_url)
    defaults = default()

    attrs =
      Enum.reduce(keys, %{}, fn k, acc ->
        val =
          case Map.fetch(map, k) do
            {:ok, v} -> v
            :error ->
              case Map.fetch(map, String.to_existing_atom(k)) do
                {:ok, v} -> v
                :error -> Map.get(defaults, String.to_existing_atom(k))
              end
          end
        Map.put(acc, String.to_existing_atom(k), val)
      end)

    struct(__MODULE__, attrs)
  end
end
