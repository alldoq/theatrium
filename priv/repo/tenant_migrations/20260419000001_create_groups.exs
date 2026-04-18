defmodule Atrium.Repo.TenantMigrations.CreateGroups do
  use Ecto.Migration

  def change do
    create table(:groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :string
      add :kind, :string, null: false, default: "custom"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:groups, [:slug])
  end
end
