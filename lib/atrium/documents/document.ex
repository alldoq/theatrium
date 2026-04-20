defmodule Atrium.Documents.Document do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft in_review approved archived)
  @kinds ~w(rich_text file)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "documents" do
    field :title, :string
    field :section_key, :string
    field :subsection_slug, :string
    field :status, :string, default: "draft"
    field :kind, :string, default: "rich_text"
    field :body_html, :string
    field :current_version, :integer, default: 1
    field :author_id, :binary_id
    field :approved_by_id, :binary_id
    field :approved_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(doc, attrs) do
    doc
    |> cast(attrs, [:title, :section_key, :subsection_slug, :body_html, :author_id, :kind])
    |> validate_required([:title, :section_key, :author_id])
    |> validate_length(:title, min: 1, max: 500)
    |> validate_inclusion(:kind, @kinds)
    |> sanitize_body_html()
  end

  def file_changeset(doc, attrs) do
    doc
    |> cast(attrs, [:title, :section_key, :subsection_slug, :author_id])
    |> validate_required([:title, :section_key, :author_id])
    |> validate_length(:title, min: 1, max: 500)
    |> put_change(:kind, "file")
  end

  def update_changeset(doc, attrs) do
    doc
    |> cast(attrs, [:title, :body_html])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 500)
    |> sanitize_body_html()
  end

  def status_changeset(doc, status, extra_attrs \\ %{}) do
    doc
    |> cast(Map.merge(%{status: status}, extra_attrs), [:status, :approved_by_id, :approved_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  def version_bump_changeset(%Ecto.Changeset{} = cs) do
    current = get_field(cs, :current_version)
    change(cs, current_version: current + 1)
  end

  def version_bump_changeset(%__MODULE__{} = doc) do
    change(doc, current_version: doc.current_version + 1)
  end

  defp sanitize_body_html(changeset) do
    case get_change(changeset, :body_html) do
      nil -> changeset
      html -> put_change(changeset, :body_html, HtmlSanitizeEx.basic_html(html))
    end
  end
end
