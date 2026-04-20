defmodule Atrium.Repo.Migrations.CreateToolRequests do
  use Ecto.Migration

  def change do
    create table(:tool_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tool_id, references(:tool_links, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, :binary_id, null: false
      add :user_name, :string
      add :user_email, :string
      add :message, :text
      add :status, :string, default: "pending", null: false
      add :reviewed_by, :binary_id
      add :reviewed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:tool_requests, [:tool_id])
    create index(:tool_requests, [:user_id])
    create index(:tool_requests, [:status])
  end
end
