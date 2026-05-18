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

    customers = Repo.all(query, prefix: prefix)

    counts =
      Repo.all(
        from(p in Person, group_by: p.customer_id, select: {p.customer_id, count(p.id)}),
        prefix: prefix
      )
      |> Map.new()

    Enum.map(customers, fn c -> Map.put(c, :people_count, Map.get(counts, c.id, 0)) end)
  end

  def get_customer!(prefix, id) do
    Customer
    |> Repo.get!(id, prefix: prefix)
    |> Repo.preload([people: from(p in Person, order_by: [desc: p.primary, asc: p.name])], prefix: prefix)
  end

  def create_customer(prefix, attrs, user) do
    changeset = Customer.changeset(%Customer{}, attrs)

    Repo.transaction(fn ->
      with {:ok, customer} <- Repo.insert(changeset, prefix: prefix),
           {:ok, _} <- Atrium.Audit.log(prefix, "customer.created", %{actor: {:user, user.id}, resource: {"Customer", customer.id}}) do
        customer
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_customer(prefix, %Customer{} = customer, attrs, user) do
    changeset = Customer.changeset(customer, attrs)

    Repo.transaction(fn ->
      with {:ok, updated} <- Repo.update(changeset, prefix: prefix),
           {:ok, _} <- Atrium.Audit.log(prefix, "customer.updated", %{actor: {:user, user.id}, resource: {"Customer", updated.id}}) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete_customer(prefix, %Customer{} = customer, user) do
    Repo.transaction(fn ->
      with {:ok, deleted} <- Repo.delete(customer, prefix: prefix),
           {:ok, _} <- Atrium.Audit.log(prefix, "customer.deleted", %{actor: {:user, user.id}, resource: {"Customer", deleted.id}}) do
        deleted
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def change_customer(%Customer{} = customer, attrs \\ %{}) do
    Customer.changeset(customer, attrs)
  end

  def get_person!(prefix, customer_id, person_id) do
    Repo.one!(
      from(p in Person, where: p.id == ^person_id and p.customer_id == ^customer_id),
      prefix: prefix
    )
  end

  def add_person(prefix, customer_id, attrs, user) do
    attrs = Map.put(stringify(attrs), "customer_id", customer_id)
    changeset = Person.changeset(%Person{}, attrs)

    Repo.transaction(fn ->
      with {:ok, person} <- Repo.insert(changeset, prefix: prefix),
           {:ok, _} <- Atrium.Audit.log(prefix, "customer_person.created", %{actor: {:user, user.id}, resource: {"CustomerPerson", person.id}}) do
        person
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_person(prefix, %Person{} = person, attrs, user) do
    changeset = Person.changeset(person, stringify(attrs))

    Repo.transaction(fn ->
      with {:ok, updated} <- Repo.update(changeset, prefix: prefix),
           {:ok, _} <- Atrium.Audit.log(prefix, "customer_person.updated", %{actor: {:user, user.id}, resource: {"CustomerPerson", updated.id}}) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete_person(prefix, %Person{} = person, user) do
    Repo.transaction(fn ->
      with {:ok, deleted} <- Repo.delete(person, prefix: prefix),
           {:ok, _} <- Atrium.Audit.log(prefix, "customer_person.deleted", %{actor: {:user, user.id}, resource: {"CustomerPerson", deleted.id}}) do
        deleted
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def change_person(%Person{} = person, attrs \\ %{}) do
    Person.changeset(person, attrs)
  end

  defp stringify(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
