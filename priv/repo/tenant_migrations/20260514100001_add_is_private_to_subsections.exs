defmodule Atrium.Repo.TenantMigrations.AddIsPrivateToSubsections do
  use Ecto.Migration

  def change do
    alter table(:subsections) do
      add :is_private, :boolean, default: false, null: false
    end
  end
end
