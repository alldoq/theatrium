defmodule Atrium.Projects.ProjectUpdate do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "project_updates" do
    field :project_id, :binary_id
    field :author_id, :binary_id
    field :body, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(update, attrs) do
    update
    |> cast(attrs, [:project_id, :author_id, :body])
    |> validate_required([:project_id, :author_id, :body])
    |> validate_length(:body, min: 1, max: 4000)
  end
end
