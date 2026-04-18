defmodule Atrium.Sections do
  alias Atrium.Repo
  alias Atrium.Sections.SectionCustomization

  @spec list_customizations() :: %{String.t() => SectionCustomization.t()}
  def list_customizations do
    Repo.all(SectionCustomization)
    |> Map.new(&{&1.section_key, &1})
  end

  @spec get_customization(String.t()) :: SectionCustomization.t() | nil
  def get_customization(section_key) do
    Repo.get_by(SectionCustomization, section_key: section_key)
  end

  @spec upsert_customization(String.t(), map()) :: {:ok, SectionCustomization.t()} | {:error, Ecto.Changeset.t()}
  def upsert_customization(section_key, attrs) do
    %SectionCustomization{}
    |> SectionCustomization.changeset(Map.put(attrs, :section_key, section_key))
    |> Repo.insert(
      on_conflict: {:replace, [:display_name, :icon_name, :updated_at]},
      conflict_target: :section_key
    )
  end
end
