defmodule Atrium.Forms.FormSubmission do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_submissions" do
    field :form_id, :binary_id
    field :form_version, :integer
    field :submitted_by_id, :binary_id
    field :submitted_at, :utc_datetime_usec
    field :status, :string, default: "pending"
    field :field_values, :map, default: %{}
    field :file_keys, {:array, :string}, default: []

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, [:form_id, :form_version, :submitted_by_id, :submitted_at, :field_values, :file_keys])
    |> validate_required([:form_id, :form_version, :submitted_by_id, :submitted_at])
  end

  def complete_changeset(sub) do
    change(sub, status: "completed")
  end
end
