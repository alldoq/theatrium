defmodule Atrium.Repo.TenantMigrations.CreateSubsections do
  use Ecto.Migration

  def change do
    create table(:subsections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :section_key, :string, null: false
      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:subsections, [:section_key, :slug])
  end
end
