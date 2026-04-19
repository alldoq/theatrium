defmodule Atrium.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "projects" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "active"
    field :owner_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:title, :description, :status, :owner_id])
    |> validate_required([:title, :owner_id])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_inclusion(:status, ~w(active on_hold completed archived))
  end
end
