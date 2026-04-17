defmodule Atrium.Repo.TenantMigrations.CreateIdpConfigurations do
  use Ecto.Migration

  def change do
    create table(:idp_configurations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :name, :string, null: false
      add :discovery_url, :string
      add :metadata_xml, :text
      add :client_id, :string
      add :client_secret, :binary
      add :claim_mappings, :map, null: false, default: %{}
      add :provisioning_mode, :string, null: false, default: "strict"
      add :default_group_ids, {:array, :binary_id}, null: false, default: []
      add :enabled, :boolean, null: false, default: true
      add :is_default, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:idp_configurations, [:kind])
    create index(:idp_configurations, [:enabled])
    create unique_index(:idp_configurations, [:is_default], where: "is_default = true", name: :one_default_idp)
  end
end
