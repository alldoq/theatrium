defmodule Atrium.Community.Reply do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_replies" do
    field :post_id, :binary_id
    field :author_id, :binary_id
    field :body, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(reply, attrs) do
    reply
    |> cast(attrs, [:post_id, :author_id, :body])
    |> validate_required([:post_id, :author_id, :body])
    |> validate_length(:body, min: 1, max: 4000)
  end
end
