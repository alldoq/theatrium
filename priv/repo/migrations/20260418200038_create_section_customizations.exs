defmodule Atrium.Repo.Migrations.CreateSectionCustomizations do
  use Ecto.Migration

  def change do
    create table(:section_customizations) do
      add :section_key, :string, null: false
      add :display_name, :string
      add :icon_name, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:section_customizations, [:section_key])
  end
end
