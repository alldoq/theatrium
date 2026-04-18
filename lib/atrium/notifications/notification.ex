defmodule Atrium.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_types ~w(
    document_submitted
    document_approved
    document_rejected
    form_submission
    tool_request_approved
    tool_request_rejected
    announcement
  )

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notifications" do
    field :user_id, :binary_id
    field :type, :string
    field :title, :string
    field :body, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :read_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(notification, attrs) do
    notification
    |> cast(attrs, [:user_id, :type, :title, :body, :resource_type, :resource_id])
    |> validate_required([:user_id, :type, :title])
    |> validate_length(:title, min: 1, max: 500)
    |> validate_inclusion(:type, @valid_types)
  end
end
