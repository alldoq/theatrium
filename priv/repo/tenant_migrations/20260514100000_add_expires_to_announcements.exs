defmodule Atrium.Repo.Migrations.AddExpiresToAnnouncements do
  use Ecto.Migration

  def change do
    alter table(:announcements) do
      add :expires_at, :utc_datetime_usec
    end

    create index(:announcements, [:expires_at])
  end
end
