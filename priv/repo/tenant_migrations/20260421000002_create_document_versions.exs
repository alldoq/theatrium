defmodule Atrium.Repo.TenantMigrations.CreateDocumentVersions do
  use Ecto.Migration

  def change do
    create table(:document_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :title, :string, null: false
      add :body_html, :text
      add :saved_by_id, :binary_id, null: false
      add :saved_at, :utc_datetime_usec, null: false
    end

    create index(:document_versions, [:document_id])
    create unique_index(:document_versions, [:document_id, :version])
  end
end
