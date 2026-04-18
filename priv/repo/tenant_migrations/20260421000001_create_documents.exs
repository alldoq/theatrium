defmodule Atrium.Repo.TenantMigrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :title, :string, null: false
      add :section_key, :string, null: false
      add :subsection_slug, :string, null: true
      add :status, :string, null: false, default: "draft"
      add :body_html, :text
      add :current_version, :integer, null: false, default: 1
      add :author_id, :binary_id, null: false
      add :approved_by_id, :binary_id, null: true
      add :approved_at, :utc_datetime_usec, null: true

      timestamps(type: :utc_datetime_usec)
    end

    create index(:documents, [:section_key])
    create index(:documents, [:section_key, :subsection_slug])
    create index(:documents, [:author_id])
    create index(:documents, [:status])
  end
end
