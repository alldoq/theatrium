defmodule Atrium.Home.Announcement do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "announcements" do
    field :title, :string
    field :body_html, :string, default: ""
    field :pinned, :boolean, default: false
    field :author_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(ann, attrs) do
    ann
    |> cast(attrs, [:title, :body_html, :pinned, :author_id])
    |> validate_required([:title, :author_id])
    |> validate_length(:title, min: 1, max: 300)
    |> sanitize()
  end

  def update_changeset(ann, attrs) do
    ann
    |> cast(attrs, [:title, :body_html, :pinned])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 300)
    |> sanitize()
  end

  defp sanitize(cs) do
    case get_change(cs, :body_html) do
      nil -> cs
      html -> put_change(cs, :body_html, HtmlSanitizeEx.basic_html(html))
    end
  end
end
