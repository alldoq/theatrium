defmodule Atrium.Repo.TenantMigrations.CreateCommunity do
  use Ecto.Migration

  def change do
    create table(:community_posts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :author_id, :binary_id, null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :pinned, :boolean, null: false, default: false
      timestamps(type: :timestamptz)
    end

    create index(:community_posts, [:inserted_at])

    create table(:community_replies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :post_id, references(:community_posts, type: :binary_id, on_delete: :delete_all), null: false
      add :author_id, :binary_id, null: false
      add :body, :text, null: false
      timestamps(type: :timestamptz)
    end

    create index(:community_replies, [:post_id])
  end
end
