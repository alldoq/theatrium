defmodule Atrium.Documents.DocumentFile do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "document_files" do
    field :version, :integer
    field :file_name, :string
    field :mime_type, :string
    field :byte_size, :integer
    field :storage_path, :string
    field :wrapped_key, :binary
    field :iv, :binary
    field :auth_tag, :binary
    field :checksum_sha256, :string

    belongs_to :document, Atrium.Documents.Document
    field :uploaded_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(document_id version file_name mime_type byte_size storage_path
               wrapped_key iv auth_tag checksum_sha256 uploaded_by_id)a

  def changeset(doc_file, attrs) do
    doc_file
    |> cast(attrs, @required)
    |> validate_required(@required)
    |> validate_number(:byte_size, greater_than_or_equal_to: 0)
    |> validate_number(:version, greater_than_or_equal_to: 1)
  end
end
