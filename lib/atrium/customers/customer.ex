defmodule Atrium.Customers.Customer do
  use Ecto.Schema
  import Ecto.Changeset

  alias Atrium.Customers.Person

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "customers" do
    field :name, :string
    field :website, :string
    field :notes, :string
    field :people_count, :integer, virtual: true

    has_many :people, Person

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [:name, :website, :notes])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
