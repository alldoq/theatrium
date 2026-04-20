defmodule Atrium.Tools.ToolRequest do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending approved rejected)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tool_requests" do
    field :tool_id, :binary_id
    field :user_id, :binary_id
    field :user_name, :string
    field :user_email, :string
    field :message, :string
    field :status, :string, default: "pending"
    field :reviewed_by, :binary_id
    field :reviewed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(req, attrs) do
    req
    |> cast(attrs, [:tool_id, :user_id, :user_name, :user_email, :message])
    |> validate_required([:tool_id, :user_id, :user_name, :user_email])
    |> validate_length(:message, max: 1000)
  end

  def review_changeset(req, status, reviewer_id) do
    req
    |> change(status: status, reviewed_by: reviewer_id, reviewed_at: DateTime.utc_now())
    |> validate_inclusion(:status, @statuses)
  end
end
