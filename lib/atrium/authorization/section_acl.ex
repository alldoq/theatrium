defmodule Atrium.Authorization.SectionAcl do
  use Ecto.Schema
  import Ecto.Changeset

  @principal_types ~w(user group)
  @capabilities ~w(view edit approve)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "section_acls" do
    field :section_key, :string
    field :principal_type, :string
    field :principal_id, :binary_id
    field :capability, :string
    field :granted_by, :binary_id
    field :granted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(acl, attrs) do
    acl
    |> cast(attrs, [:section_key, :principal_type, :principal_id, :capability, :granted_by])
    |> validate_required([:section_key, :principal_type, :principal_id, :capability])
    |> validate_inclusion(:principal_type, @principal_types)
    |> validate_inclusion(:capability, @capabilities)
    |> validate_known_section()
    |> unique_constraint([:section_key, :principal_type, :principal_id, :capability],
      name: :section_acls_unique)
  end

  defp validate_known_section(cs) do
    case get_field(cs, :section_key) do
      nil -> cs
      key ->
        if Atrium.Authorization.SectionRegistry.get(key),
          do: cs,
          else: add_error(cs, :section_key, "unknown section")
    end
  end
end
