defmodule Atrium.Authorization.Subsection do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "subsections" do
    field :section_key, :string
    field :slug, :string
    field :name, :string
    field :description, :string
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(ss, attrs) do
    ss
    |> cast(attrs, [:section_key, :slug, :name, :description])
    |> validate_required([:section_key, :slug, :name])
    |> validate_format(:slug, ~r/^[a-z0-9_-]+$/)
    |> validate_section_supports_subsections()
    |> unique_constraint([:section_key, :slug])
  end

  defp validate_section_supports_subsections(cs) do
    case get_field(cs, :section_key) do
      nil -> cs
      key ->
        section = Atrium.Authorization.SectionRegistry.get(key)
        cond do
          is_nil(section) -> add_error(cs, :section_key, "unknown section")
          not section.supports_subsections -> add_error(cs, :section_key, "section does not support subsections")
          true -> cs
        end
    end
  end
end
