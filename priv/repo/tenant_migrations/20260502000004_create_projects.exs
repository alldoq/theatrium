defmodule Atrium.Repo.TenantMigrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "active"
      add :owner_id, :binary_id, null: false
      timestamps(type: :timestamptz)
    end

    create table(:project_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, :binary_id, null: false
      add :role, :string, null: false, default: "member"
      timestamps(type: :timestamptz)
    end

    create unique_index(:project_members, [:project_id, :user_id])
    create index(:project_members, [:project_id])

    create table(:project_updates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :author_id, :binary_id, null: false
      add :body, :text, null: false
      timestamps(type: :timestamptz)
    end

    create index(:project_updates, [:project_id])
  end
end
