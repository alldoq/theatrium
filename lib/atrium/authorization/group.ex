defmodule Atrium.Authorization.Group do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(system custom)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "groups" do
    field :slug, :string
    field :name, :string
    field :description, :string
    field :kind, :string, default: "custom"
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(group, attrs) do
    group
    |> cast(attrs, [:slug, :name, :description, :kind])
    |> validate_required([:slug, :name])
    |> validate_format(:slug, ~r/^[a-z0-9_]+$/, message: "lowercase alphanumeric + underscore")
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint(:slug)
  end

  def update_changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
  end
end
