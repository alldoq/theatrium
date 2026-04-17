defmodule Atrium.Accounts.IdpConfiguration do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(oidc saml)
  @modes ~w(strict auto_create link_only)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "idp_configurations" do
    field :kind, :string
    field :name, :string
    field :discovery_url, :string
    field :metadata_xml, :string
    field :client_id, :string
    field :client_secret, Atrium.Accounts.EncryptedSecret, redact: true
    field :claim_mappings, :map, default: %{}
    field :provisioning_mode, :string, default: "strict"
    field :default_group_ids, {:array, :binary_id}, default: []
    field :enabled, :boolean, default: true
    field :is_default, :boolean, default: false
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(idp, attrs) do
    idp
    |> cast(attrs, [:kind, :name, :discovery_url, :metadata_xml, :client_id, :client_secret,
                    :claim_mappings, :provisioning_mode, :default_group_ids, :enabled, :is_default])
    |> validate_required([:kind, :name])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:provisioning_mode, @modes)
    |> validate_by_kind()
    |> unique_constraint(:is_default, name: :one_default_idp)
  end

  def update_changeset(idp, attrs), do: create_changeset(idp, attrs)

  def kinds, do: @kinds
  def modes, do: @modes

  defp validate_by_kind(cs) do
    case get_field(cs, :kind) do
      "oidc" -> validate_required(cs, [:discovery_url, :client_id, :client_secret])
      "saml" -> validate_required(cs, [:metadata_xml])
      _ -> cs
    end
  end
end
