defmodule Atrium.Repo.TenantMigrations.AddKindToDocuments do
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add :kind, :string, null: false, default: "rich_text"
    end

    create index(:documents, [:kind])
  end
end
