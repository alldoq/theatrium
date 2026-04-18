defmodule Atrium.Audit.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "audit_events" do
    field :actor_id, :binary_id
    field :actor_type, :string
    field :action, :string
    field :resource_type, :string
    field :resource_id, :string
    field :changes, :map, default: %{}
    field :context, :map, default: %{}
    field :occurred_at, :utc_datetime_usec
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:actor_id, :actor_type, :action, :resource_type, :resource_id, :changes, :context, :occurred_at])
    |> validate_required([:actor_type, :action, :occurred_at])
  end
end
