defmodule Atrium.Home.QuickLink do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "quick_links" do
    field :label, :string
    field :url, :string
    field :icon, :string, default: "link"
    field :position, :integer, default: 0
    field :author_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:label, :url, :icon, :position, :author_id])
    |> validate_required([:label, :url, :author_id])
    |> validate_length(:label, min: 1, max: 100)
    |> validate_format(:url, ~r/^https?:\/\//, message: "must start with http:// or https://")
  end

  def update_changeset(link, attrs) do
    link
    |> cast(attrs, [:label, :url, :icon, :position])
    |> validate_required([:label, :url])
    |> validate_length(:label, min: 1, max: 100)
    |> validate_format(:url, ~r/^https?:\/\//, message: "must start with http:// or https://")
  end
end
