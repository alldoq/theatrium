defmodule Atrium.Sections.SectionCustomization do
  use Ecto.Schema
  import Ecto.Changeset

  schema "section_customizations" do
    field :section_key, :string
    field :display_name, :string
    field :icon_name, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:section_key, :display_name, :icon_name])
    |> validate_required([:section_key])
    |> unique_constraint(:section_key)
  end
end
