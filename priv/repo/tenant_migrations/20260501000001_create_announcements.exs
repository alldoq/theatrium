defmodule Atrium.Repo.Migrations.CreateAnnouncements do
  use Ecto.Migration
  def change do
    create table(:announcements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :body_html, :text, default: ""
      add :pinned, :boolean, default: false, null: false
      add :author_id, :binary_id
      timestamps(type: :utc_datetime_usec)
    end
    create index(:announcements, [:inserted_at])
    create index(:announcements, [:pinned])
  end
end
