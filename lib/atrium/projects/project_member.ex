defmodule Atrium.Projects.ProjectMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "project_members" do
    field :project_id, :binary_id
    field :user_id, :binary_id
    field :role, :string, default: "member"
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:project_id, :user_id, :role])
    |> validate_required([:project_id, :user_id])
    |> validate_inclusion(:role, ~w(lead member))
    |> unique_constraint([:project_id, :user_id])
  end
end
