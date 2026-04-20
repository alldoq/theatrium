defmodule Atrium.Tools.ToolLink do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(link download request)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tool_links" do
    field :label, :string
    field :url, :string
    field :description, :string
    field :icon, :string, default: "link"
    field :kind, :string, default: "link"
    field :position, :integer, default: 0
    field :author_id, :binary_id
    field :file_path, :string
    field :file_name, :string
    field :file_size, :integer
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(tool, attrs) do
    tool
    |> cast(attrs, [:label, :url, :description, :icon, :kind, :position, :author_id])
    |> validate_required([:label, :kind, :author_id])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:label, min: 1, max: 100)
    |> validate_url_for_kind()
  end

  def file_changeset(tool, attrs) do
    tool
    |> cast(attrs, [:file_path, :file_name, :file_size])
    |> validate_required([:file_path, :file_name])
  end

  def kinds, do: @kinds

  defp validate_url_for_kind(cs) do
    case get_field(cs, :kind) do
      "link" ->
        cs
        |> validate_required([:url])
        |> validate_format(:url, ~r/^https?:\/\//, message: "must start with http:// or https://")
      _ ->
        cs
    end
  end
end
