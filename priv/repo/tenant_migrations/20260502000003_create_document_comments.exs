defmodule Atrium.Repo.TenantMigrations.CreateDocumentComments do
  use Ecto.Migration

  def change do
    create table(:document_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all), null: false
      add :author_id, :binary_id, null: false
      add :body, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:document_comments, [:document_id])
  end
end
