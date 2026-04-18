defmodule Atrium.Repo.Migrations.AddProfileFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string
      add :department, :string
      add :phone, :string
      add :bio, :text
      add :avatar_url, :string
    end
  end
end
