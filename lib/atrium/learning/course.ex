defmodule Atrium.Learning.Course do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "courses" do
    field :title, :string
    field :description, :string
    field :category, :string
    field :status, :string, default: "draft"
    field :created_by_id, :binary_id

    has_many :materials, Atrium.Learning.CourseMaterial, foreign_key: :course_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(course, attrs) do
    course
    |> cast(attrs, [:title, :description, :category, :status, :created_by_id])
    |> validate_required([:title, :created_by_id])
    |> validate_inclusion(:status, ~w(draft published archived))
    |> validate_length(:title, max: 200)
  end
end
