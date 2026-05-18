defmodule Atrium.CustomersTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.{Accounts, Customers}
  alias Atrium.Customers.Customer
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup do
    slug = "cust_#{:erlang.unique_integer([:positive])}"
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: slug, name: "Customers Test"})
    {:ok, _} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop(slug) end)
    prefix = Triplex.to_prefix(slug)

    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{
      email: "user_#{System.unique_integer([:positive])}@example.com",
      name: "Test User"
    })
    {:ok, user} = Accounts.activate_user_with_password(prefix, user, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })

    {:ok, prefix: prefix, user: user}
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

  test "create_customer / list_customers / get_customer!", %{prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co", "website" => "acme.com"}, user)
    assert c.name == "Acme Co"

    assert [listed] = Customers.list_customers(prefix)
    assert listed.id == c.id

    fetched = Customers.get_customer!(prefix, c.id)
    assert fetched.id == c.id
    assert fetched.people == []
  end

  test "list_customers filters by name query", %{prefix: prefix, user: user} do
    {:ok, _} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    {:ok, _} = Customers.create_customer(prefix, %{"name" => "Globex"}, user)

    assert [only] = Customers.list_customers(prefix, q: "acme")
    assert only.name == "Acme Co"
  end

  test "update_customer changes fields", %{prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    {:ok, updated} = Customers.update_customer(prefix, c, %{"name" => "Acme Inc"}, user)
    assert updated.name == "Acme Inc"
  end

  test "delete_customer removes the customer", %{prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    {:ok, _} = Customers.delete_customer(prefix, c, user)
    assert Customers.list_customers(prefix) == []
  end

  test "add_person / get_person! / update_person / delete_person", %{prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)

    {:ok, p} = Customers.add_person(prefix, c.id, %{"name" => "Bob", "email" => "bob@acme.com"}, user)
    assert p.customer_id == c.id

    fetched = Customers.get_person!(prefix, c.id, p.id)
    assert fetched.id == p.id

    {:ok, updated} = Customers.update_person(prefix, fetched, %{"job_title" => "CEO"}, user)
    assert updated.job_title == "CEO"

    {:ok, _} = Customers.delete_person(prefix, updated, user)
    assert Customers.get_customer!(prefix, c.id).people == []
  end

  test "get_person! rejects a person from a different customer", %{prefix: prefix, user: user} do
    {:ok, c1} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    {:ok, c2} = Customers.create_customer(prefix, %{"name" => "Globex"}, user)
    {:ok, p} = Customers.add_person(prefix, c1.id, %{"name" => "Bob"}, user)

    assert_raise Ecto.NoResultsError, fn ->
      Customers.get_person!(prefix, c2.id, p.id)
    end
  end

  test "deleting a customer cascades to its people", %{prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    {:ok, _} = Customers.add_person(prefix, c.id, %{"name" => "Bob"}, user)

    {:ok, _} = Customers.delete_customer(prefix, c, user)

    assert Atrium.Repo.all(Atrium.Customers.Person, prefix: prefix) == []
  end
end
