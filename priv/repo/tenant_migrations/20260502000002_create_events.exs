defmodule Atrium.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text
      add :location, :string
      add :starts_at, :utc_datetime_usec, null: false
      add :ends_at, :utc_datetime_usec
      add :all_day, :boolean, default: false, null: false
      add :author_id, :binary_id, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:events, [:starts_at])
    create index(:events, [:author_id])
  end
end
