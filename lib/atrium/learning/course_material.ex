defmodule Atrium.Learning.CourseMaterial do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "course_materials" do
    field :type, :string
    field :position, :integer, default: 0
    field :title, :string
    field :document_id, :binary_id
    field :url, :string
    belongs_to :course, Atrium.Learning.Course, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(material, attrs) do
    material
    |> cast(attrs, [:course_id, :type, :position, :title, :document_id, :url])
    |> validate_required([:course_id, :type, :title, :position])
    |> validate_inclusion(:type, ~w(document url))
    |> validate_url()
    |> validate_document()
  end

  defp validate_url(cs) do
    case get_field(cs, :type) do
      "url" ->
        cs
        |> validate_required([:url])
        |> validate_format(:url, ~r/\Ahttps?:\/\//,
             message: "must start with http:// or https://")
      _ -> cs
    end
  end

  defp validate_document(cs) do
    case get_field(cs, :type) do
      "document" -> validate_required(cs, [:document_id])
      _ -> cs
    end
  end
end
