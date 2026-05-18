defmodule Atrium.Customers.Person do
  use Ecto.Schema
  import Ecto.Changeset

  alias Atrium.Customers.Customer

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  schema "customer_people" do
    field :name, :string
    field :job_title, :string
    field :email, :string
    field :phone, :string
    field :primary, :boolean, default: false

    belongs_to :customer, Customer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(person, attrs) do
    person
    |> cast(attrs, [:name, :job_title, :email, :phone, :primary, :customer_id])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_format(:email, @email_regex, message: "must be a valid email")
  end
end
