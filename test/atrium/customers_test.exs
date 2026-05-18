defmodule Atrium.CustomersTest do
  use AtriumWeb.ConnCase, async: false

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
end
