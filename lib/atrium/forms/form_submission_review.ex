defmodule Atrium.Forms.FormSubmissionReview do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending completed)
  @reviewer_types ~w(user email)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_submission_reviews" do
    field :submission_id, :binary_id
    field :reviewer_type, :string
    field :reviewer_id, :binary_id
    field :reviewer_email, :string
    field :status, :string, default: "pending"
    field :completed_at, :utc_datetime_usec
    field :completed_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(review, attrs) do
    review
    |> cast(attrs, [:submission_id, :reviewer_type, :reviewer_id, :reviewer_email])
    |> validate_required([:submission_id, :reviewer_type])
    |> validate_inclusion(:reviewer_type, @reviewer_types)
  end

  def complete_changeset(review, completed_by_id) do
    review
    |> change(%{
      status: "completed",
      completed_at: DateTime.utc_now(),
      completed_by_id: completed_by_id
    })
  end
end
