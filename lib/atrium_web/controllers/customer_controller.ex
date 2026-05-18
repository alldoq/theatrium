defmodule AtriumWeb.CustomerController do
  use AtriumWeb, :controller

  alias Atrium.Customers

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "customers"}]
       when action in [:index, :show]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: {:section, "customers"}]
       when action in [
              :new,
              :create,
              :edit,
              :update,
              :delete,
              :create_person,
              :edit_person,
              :update_person,
              :delete_person
            ]

  def index(conn, params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "customers"})
    customers = Customers.list_customers(prefix, q: params["q"])
    render(conn, :index, customers: customers, query: params["q"] || "", can_edit: can_edit)
  end

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "customers"})
    customer = Customers.get_customer!(prefix, id)
    render(conn, :show, customer: customer, can_edit: can_edit)
  end

  def new(conn, _params) do
    changeset = Customers.change_customer(%Atrium.Customers.Customer{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"customer" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Customers.create_customer(prefix, params, user) do
      {:ok, customer} ->
        conn
        |> put_flash(:info, "Customer created.")
        |> redirect(to: ~p"/customers/#{customer.id}")

      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    customer = Customers.get_customer!(prefix, id)
    changeset = Customers.change_customer(customer)
    render(conn, :edit, customer: customer, changeset: changeset)
  end

  def update(conn, %{"id" => id, "customer" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    customer = Customers.get_customer!(prefix, id)

    case Customers.update_customer(prefix, customer, params, user) do
      {:ok, customer} ->
        conn
        |> put_flash(:info, "Customer updated.")
        |> redirect(to: ~p"/customers/#{customer.id}")

      {:error, changeset} ->
        render(conn, :edit, customer: customer, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    customer = Customers.get_customer!(prefix, id)
    {:ok, _} = Customers.delete_customer(prefix, customer, user)

    conn
    |> put_flash(:info, "Customer deleted.")
    |> redirect(to: ~p"/customers")
  end
end
