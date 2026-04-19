defmodule Atrium.Community.Post do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_posts" do
    field :author_id, :binary_id
    field :title, :string
    field :body, :string
    field :pinned, :boolean, default: false
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:author_id, :title, :body, :pinned])
    |> validate_required([:author_id, :title, :body])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:body, min: 1, max: 10000)
  end
end
