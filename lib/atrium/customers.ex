defmodule Atrium.Customers do
  @moduledoc "Context for the Customers contact book section."

  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Customers.{Customer, Person}

  def list_customers(prefix, opts \\ []) do
    query = from(c in Customer, order_by: [asc: c.name])

    query =
      case Keyword.get(opts, :q) do
        nil -> query
        "" -> query
        q ->
          like = "%#{String.downcase(q)}%"
          from(c in query, where: like(fragment("lower(?)", c.name), ^like))
      end

    Repo.all(query, prefix: prefix)
  end

  def get_customer!(prefix, id) do
    Customer
    |> Repo.get!(id, prefix: prefix)
    |> Repo.preload([people: from(p in Person, order_by: [desc: p.primary, asc: p.name])], prefix: prefix)
  end

  def create_customer(prefix, attrs) do
    %Customer{}
    |> Customer.changeset(attrs)
    |> Repo.insert(prefix: prefix)
  end

  def update_customer(prefix, %Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update(prefix: prefix)
  end

  def delete_customer(prefix, %Customer{} = customer) do
    Repo.delete(customer, prefix: prefix)
  end

  def change_customer(%Customer{} = customer, attrs \\ %{}) do
    Customer.changeset(customer, attrs)
  end
end
