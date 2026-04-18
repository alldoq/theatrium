defmodule Atrium.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "events" do
    field :title, :string
    field :description, :string
    field :location, :string
    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec
    field :all_day, :boolean, default: false
    field :author_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:title, :description, :location, :starts_at, :ends_at, :all_day, :author_id])
    |> validate_required([:title, :starts_at, :author_id])
    |> validate_length(:title, min: 1, max: 300)
    |> validate_ends_after_starts()
  end

  defp validate_ends_after_starts(cs) do
    starts = get_field(cs, :starts_at)
    ends = get_field(cs, :ends_at)

    if starts && ends && DateTime.compare(ends, starts) == :lt do
      add_error(cs, :ends_at, "must be after start time")
    else
      cs
    end
  end
end
