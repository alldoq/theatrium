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

  def create_person(conn, %{"id" => customer_id, "person" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    # Ensures a bogus customer id returns 404 before attempting the insert.
    _customer = Customers.get_customer!(prefix, customer_id)

    case Customers.add_person(prefix, customer_id, params, user) do
      {:ok, _person} ->
        conn
        |> put_flash(:info, "Person added.")
        |> redirect(to: ~p"/customers/#{customer_id}")

      {:error, changeset} ->
        conn
        |> put_flash(:error, error_message(changeset))
        |> redirect(to: ~p"/customers/#{customer_id}")
    end
  end

  def edit_person(conn, %{"id" => customer_id, "pid" => person_id}) do
    prefix = conn.assigns.tenant_prefix
    person = Customers.get_person!(prefix, customer_id, person_id)
    changeset = Customers.change_person(person)
    render(conn, :edit_person, customer_id: customer_id, person: person, changeset: changeset)
  end

  def update_person(conn, %{"id" => customer_id, "pid" => person_id, "person" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    person = Customers.get_person!(prefix, customer_id, person_id)

    case Customers.update_person(prefix, person, params, user) do
      {:ok, _person} ->
        conn
        |> put_flash(:info, "Person updated.")
        |> redirect(to: ~p"/customers/#{customer_id}")

      {:error, changeset} ->
        render(conn, :edit_person, customer_id: customer_id, person: person, changeset: changeset)
    end
  end

  def delete_person(conn, %{"id" => customer_id, "pid" => person_id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    person = Customers.get_person!(prefix, customer_id, person_id)
    {:ok, _} = Customers.delete_person(prefix, person, user)

    conn
    |> put_flash(:info, "Person removed.")
    |> redirect(to: ~p"/customers/#{customer_id}")
  end

  defp error_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Enum.map(fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end
end
