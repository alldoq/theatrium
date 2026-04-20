defmodule Atrium.Repo.TenantMigrations.CreateDocumentFiles do
  use Ecto.Migration

  def change do
    create table(:document_files, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :file_name, :string, null: false
      add :mime_type, :string, null: false
      add :byte_size, :bigint, null: false
      add :storage_path, :string, null: false
      add :wrapped_key, :binary, null: false
      add :iv, :binary, null: false
      add :auth_tag, :binary, null: false
      add :checksum_sha256, :string, null: false
      add :uploaded_by_id, :binary_id, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:document_files, [:document_id, :version])
    create index(:document_files, [:document_id])
  end
end
