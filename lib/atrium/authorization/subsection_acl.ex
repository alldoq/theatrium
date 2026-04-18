defmodule Atrium.Authorization.SubsectionAcl do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "subsection_acls" do
    field :section_key, :string
    field :subsection_slug, :string
    field :principal_type, :string
    field :principal_id, :binary_id
    field :capability, :string
    field :granted_by, :binary_id
    field :granted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(acl, attrs) do
    acl
    |> cast(attrs, [:section_key, :subsection_slug, :principal_type, :principal_id, :capability, :granted_by])
    |> validate_required([:section_key, :subsection_slug, :principal_type, :principal_id, :capability])
    |> validate_inclusion(:principal_type, ~w(user group))
    |> validate_inclusion(:capability, ~w(view edit approve))
    |> unique_constraint([:section_key, :subsection_slug, :principal_type, :principal_id, :capability],
      name: :subsection_acls_unique)
  end
end
