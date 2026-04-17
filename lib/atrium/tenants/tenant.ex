defmodule Atrium.Tenants.Tenant do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(provisioning active suspended)
  @slug_regex ~r/^[a-z][a-z0-9_]{1,62}$/

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "tenants" do
    field :slug, :string
    field :name, :string
    field :status, :string, default: "provisioning"
    field :theme, :map, default: %{}
    field :enabled_sections, {:array, :string}, default: []
    field :allow_local_login, :boolean, default: true
    field :session_idle_timeout_minutes, :integer, default: 480
    field :session_absolute_timeout_days, :integer, default: 30
    field :audit_retention_days, :integer, default: 2555
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [
      :slug,
      :name,
      :theme,
      :enabled_sections,
      :allow_local_login,
      :session_idle_timeout_minutes,
      :session_absolute_timeout_days,
      :audit_retention_days
    ])
    |> validate_required([:slug, :name])
    |> validate_format(:slug, @slug_regex, message: "must be lowercase alphanumeric with underscores, starting with a letter")
    |> validate_length(:slug, min: 2, max: 63)
    |> unique_constraint(:slug)
  end

  def update_changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [
      :name,
      :theme,
      :enabled_sections,
      :allow_local_login,
      :session_idle_timeout_minutes,
      :session_absolute_timeout_days,
      :audit_retention_days
    ])
  end

  def status_changeset(tenant, status) do
    tenant
    |> change(status: status)
    |> validate_inclusion(:status, @statuses, message: "must be one of: #{Enum.join(@statuses, ", ")}")
  end

  def statuses, do: @statuses
end
