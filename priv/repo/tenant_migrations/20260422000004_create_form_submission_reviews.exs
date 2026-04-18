defmodule Atrium.Repo.TenantMigrations.CreateFormSubmissionReviews do
  use Ecto.Migration

  def change do
    create table(:form_submission_reviews, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :submission_id, references(:form_submissions, type: :binary_id, on_delete: :delete_all), null: false
      add :reviewer_type, :string, null: false
      add :reviewer_id, :binary_id, null: true
      add :reviewer_email, :string, null: true
      add :status, :string, null: false, default: "pending"
      add :completed_at, :utc_datetime_usec, null: true
      add :completed_by_id, :binary_id, null: true

      timestamps(type: :utc_datetime_usec)
    end

    create index(:form_submission_reviews, [:submission_id])
    create index(:form_submission_reviews, [:reviewer_id])
    create index(:form_submission_reviews, [:status])
  end
end
