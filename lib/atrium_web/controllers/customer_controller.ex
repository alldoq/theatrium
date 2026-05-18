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
end
