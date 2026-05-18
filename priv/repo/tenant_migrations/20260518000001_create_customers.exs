defmodule Atrium.Repo.TenantMigrations.CreateCustomers do
  use Ecto.Migration

  def change do
    create table(:customers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :website, :string
      add :notes, :text
      timestamps(type: :utc_datetime_usec)
    end

    create table(:customer_people, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :customer_id, references(:customers, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :job_title, :string
      add :email, :string
      add :phone, :string
      add :primary, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:customer_people, [:customer_id])
  end
end
