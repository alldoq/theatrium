defmodule Atrium.Repo.Migrations.CreateLearningTables do
  use Ecto.Migration

  def change do
    create table(:courses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text
      add :category, :string
      add :status, :string, null: false, default: "draft"
      add :created_by_id, :binary_id, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:courses, [:status])
    create index(:courses, [:category])

    create table(:course_materials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :position, :integer, null: false, default: 0
      add :title, :string, null: false
      add :document_id, :binary_id
      add :url, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:course_materials, [:course_id])
    create index(:course_materials, [:course_id, :position])

    create table(:course_completions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, :binary_id, null: false
      add :completed_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:course_completions, [:course_id, :user_id])
    create index(:course_completions, [:user_id])
  end
end
