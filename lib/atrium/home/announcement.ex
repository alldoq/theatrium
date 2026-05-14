defmodule Atrium.Home.Announcement do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "announcements" do
    field :title, :string
    field :body_html, :string, default: ""
    field :pinned, :boolean, default: false
    field :expires_at, :utc_datetime_usec
    field :author_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(ann, attrs) do
    ann
    |> cast(normalize(attrs), [:title, :body_html, :pinned, :expires_at, :author_id])
    |> validate_required([:title, :author_id])
    |> validate_length(:title, min: 1, max: 300)
    |> sanitize()
  end

  def update_changeset(ann, attrs) do
    ann
    |> cast(normalize(attrs), [:title, :body_html, :pinned, :expires_at])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 300)
    |> sanitize()
  end

  defp normalize(attrs) do
    case Map.get(attrs, "expires_at") do
      "" -> Map.put(attrs, "expires_at", nil)
      nil -> attrs
      v when is_binary(v) ->
        v =
          case String.split(v, "T") do
            [date, time] ->
              time =
                case String.split(time, ":") do
                  [h, m] -> "#{h}:#{m}:00"
                  _ -> time
                end
              "#{date}T#{time}"
            _ -> v
          end
        case NaiveDateTime.from_iso8601(v) do
          {:ok, ndt} -> Map.put(attrs, "expires_at", DateTime.from_naive!(ndt, "Etc/UTC"))
          _ -> attrs
        end
      _ -> attrs
    end
  end

  defp sanitize(cs) do
    case get_change(cs, :body_html) do
      nil -> cs
      html -> put_change(cs, :body_html, HtmlSanitizeEx.basic_html(html))
    end
  end
end
