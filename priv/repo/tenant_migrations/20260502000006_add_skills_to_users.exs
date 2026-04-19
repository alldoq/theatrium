defmodule Atrium.Repo.TenantMigrations.AddSkillsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :skills, {:array, :string}, null: false, default: []
    end
  end
end
