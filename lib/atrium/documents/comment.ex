defmodule Atrium.Documents.Comment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "document_comments" do
    field :document_id, :binary_id
    field :author_id, :binary_id
    field :body, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:document_id, :author_id, :body])
    |> validate_required([:document_id, :author_id, :body])
    |> validate_length(:body, min: 1, max: 4000)
  end
end
