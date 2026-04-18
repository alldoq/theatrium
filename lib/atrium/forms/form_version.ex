defmodule Atrium.Forms.FormVersion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_versions" do
    field :form_id, :binary_id
    field :version, :integer
    field :fields, {:array, :map}, default: []
    field :published_by_id, :binary_id
    field :published_at, :utc_datetime_usec
  end

  # form_versions has no mutable timestamps — published_at is the canonical stamp

  def changeset(fv, attrs) do
    fv
    |> cast(attrs, [:form_id, :version, :fields, :published_by_id, :published_at])
    |> validate_required([:form_id, :version, :published_by_id, :published_at])
  end
end
