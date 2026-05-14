defmodule Atrium.Scorm.Attempt do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "scorm_attempts" do
    field :package_id, :binary_id
    field :user_id, :binary_id
    field :lesson_status, :string, default: "not attempted"
    field :score_raw, :float
    field :score_min, :float
    field :score_max, :float
    field :total_time, :string, default: "0000:00:00.00"
    field :session_time, :string
    field :suspend_data, :string
    field :cmi, :map, default: %{}
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @castable [
    :package_id,
    :user_id,
    :lesson_status,
    :score_raw,
    :score_min,
    :score_max,
    :total_time,
    :session_time,
    :suspend_data,
    :cmi,
    :started_at,
    :completed_at
  ]

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, @castable)
    |> validate_required([:package_id, :user_id])
  end
end
