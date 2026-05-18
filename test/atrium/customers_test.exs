defmodule Atrium.CustomersTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.Customers
  alias Atrium.Customers.Customer
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup do
    slug = "cust_#{:erlang.unique_integer([:positive])}"
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: slug, name: "Customers Test"})
    {:ok, _} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop(slug) end)
    {:ok, prefix: Triplex.to_prefix(slug)}
  end

  test "customer changeset requires name" do
    cs = Customer.changeset(%Customer{}, %{"website" => "x.com"})
    refute cs.valid?
    assert %{name: ["can't be blank"]} = errors_on(cs)
  end

  test "customer changeset is valid with a name" do
    cs = Customer.changeset(%Customer{}, %{"name" => "Acme Co"})
    assert cs.valid?
  end

  test "person changeset requires name" do
    cs = Atrium.Customers.Person.changeset(%Atrium.Customers.Person{}, %{"email" => "a@b.com"})
    refute cs.valid?
    assert %{name: ["can't be blank"]} = errors_on(cs)
  end

  test "person changeset rejects malformed email" do
    cs = Atrium.Customers.Person.changeset(%Atrium.Customers.Person{}, %{"name" => "Bob", "email" => "not-an-email"})
    refute cs.valid?
    assert %{email: ["must be a valid email"]} = errors_on(cs)
  end

  test "person changeset is valid without an email" do
    cs = Atrium.Customers.Person.changeset(%Atrium.Customers.Person{}, %{"name" => "Bob"})
    assert cs.valid?
  end

  test "create_customer / list_customers / get_customer!", %{prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co", "website" => "acme.com"})
    assert c.name == "Acme Co"

    assert [listed] = Customers.list_customers(prefix)
    assert listed.id == c.id

    fetched = Customers.get_customer!(prefix, c.id)
    assert fetched.id == c.id
    assert fetched.people == []
  end

  test "list_customers filters by name query", %{prefix: prefix} do
    {:ok, _} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    {:ok, _} = Customers.create_customer(prefix, %{"name" => "Globex"})

    assert [only] = Customers.list_customers(prefix, q: "acme")
    assert only.name == "Acme Co"
  end

  test "update_customer changes fields", %{prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    {:ok, updated} = Customers.update_customer(prefix, c, %{"name" => "Acme Inc"})
    assert updated.name == "Acme Inc"
  end

  test "delete_customer removes the customer", %{prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    {:ok, _} = Customers.delete_customer(prefix, c)
    assert Customers.list_customers(prefix) == []
  end

  test "add_person / get_person! / update_person / delete_person", %{prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})

    {:ok, p} = Customers.add_person(prefix, c.id, %{"name" => "Bob", "email" => "bob@acme.com"})
    assert p.customer_id == c.id

    fetched = Customers.get_person!(prefix, c.id, p.id)
    assert fetched.id == p.id

    {:ok, updated} = Customers.update_person(prefix, fetched, %{"job_title" => "CEO"})
    assert updated.job_title == "CEO"

    {:ok, _} = Customers.delete_person(prefix, updated)
    assert Customers.get_customer!(prefix, c.id).people == []
  end

  test "get_person! rejects a person from a different customer", %{prefix: prefix} do
    {:ok, c1} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    {:ok, c2} = Customers.create_customer(prefix, %{"name" => "Globex"})
    {:ok, p} = Customers.add_person(prefix, c1.id, %{"name" => "Bob"})

    assert_raise Ecto.NoResultsError, fn ->
      Customers.get_person!(prefix, c2.id, p.id)
    end
  end

  test "deleting a customer cascades to its people", %{prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    {:ok, _} = Customers.add_person(prefix, c.id, %{"name" => "Bob"})

    {:ok, _} = Customers.delete_customer(prefix, c)

    assert Atrium.Repo.all(Atrium.Customers.Person, prefix: prefix) == []
  end
end
