defmodule Atrium.Documents.DocumentVersion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "document_versions" do
    field :document_id, :binary_id
    field :version, :integer
    field :title, :string
    field :body_html, :string
    field :saved_by_id, :binary_id
    field :saved_at, :utc_datetime_usec
  end

  def changeset(dv, attrs) do
    dv
    |> cast(attrs, [:document_id, :version, :title, :body_html, :saved_by_id, :saved_at])
    |> validate_required([:document_id, :version, :title, :saved_by_id, :saved_at])
  end
end
