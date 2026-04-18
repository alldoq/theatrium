defmodule Atrium.Sections do
  import Ecto.Query
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
    existing = get_customization(section_key) || %SectionCustomization{}
    existing
    |> SectionCustomization.changeset(Map.put(attrs, :section_key, section_key))
    |> Repo.insert_or_update()
  end
end
