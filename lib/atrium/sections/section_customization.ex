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
    |> validate_length(:display_name, max: 80)
    |> validate_icon_name()
    |> unique_constraint(:section_key)
  end

  defp validate_icon_name(changeset) do
    case Ecto.Changeset.get_change(changeset, :icon_name) do
      nil -> changeset
      _name -> validate_inclusion(changeset, :icon_name, AtriumWeb.Heroicons.names())
    end
  end
end
