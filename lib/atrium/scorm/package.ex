defmodule Atrium.Scorm.Package do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "scorm_packages" do
    field :course_id, :binary_id
    field :title, :string
    field :version, :string, default: "1.2"
    field :launch_url, :string
    field :manifest_json, :map
    field :storage_path, :string
    field :byte_size, :integer
    field :uploaded_by_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(pkg, attrs) do
    pkg
    |> cast(attrs, [
      :course_id,
      :title,
      :version,
      :launch_url,
      :manifest_json,
      :storage_path,
      :byte_size,
      :uploaded_by_id
    ])
    |> validate_required([:course_id, :title, :version, :launch_url, :storage_path])
  end
end
