defmodule Atrium.Forms.Form do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft published archived)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "forms" do
    field :title, :string
    field :section_key, :string
    field :subsection_slug, :string
    field :status, :string, default: "draft"
    field :current_version, :integer, default: 1
    field :author_id, :binary_id
    field :notification_recipients, {:array, :map}, default: []

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(form, attrs) do
    form
    |> cast(attrs, [:title, :section_key, :subsection_slug, :author_id, :notification_recipients])
    |> validate_required([:title, :section_key, :author_id])
    |> validate_length(:title, min: 1, max: 500)
  end

  def update_changeset(form, attrs) do
    form
    |> cast(attrs, [:title, :subsection_slug, :notification_recipients])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 500)
  end

  def status_changeset(form, status) do
    form
    |> cast(%{status: status}, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  def version_bump_changeset(%Ecto.Changeset{} = cs) do
    current = get_field(cs, :current_version)
    change(cs, current_version: current + 1)
  end
end
