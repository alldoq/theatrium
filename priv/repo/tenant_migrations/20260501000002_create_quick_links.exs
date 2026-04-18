defmodule Atrium.Repo.Migrations.CreateQuickLinks do
  use Ecto.Migration
  def change do
    create table(:quick_links, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :label, :string, null: false
      add :url, :string, null: false
      add :icon, :string, default: "link"
      add :position, :integer, default: 0, null: false
      add :author_id, :binary_id
      timestamps(type: :utc_datetime_usec)
    end
    create index(:quick_links, [:position])
  end
end
