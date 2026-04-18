defmodule Atrium.Learning.CourseCompletion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "course_completions" do
    belongs_to :course, Atrium.Learning.Course, type: :binary_id
    field :user_id, :binary_id
    field :completed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(completion, attrs) do
    completion
    |> cast(attrs, [:course_id, :user_id, :completed_at])
    |> validate_required([:course_id, :user_id, :completed_at])
    |> unique_constraint([:course_id, :user_id])
  end
end
