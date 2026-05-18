defmodule AtriumWeb.CustomerControllerTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.{Accounts, Authorization, Tenants, Customers}
  alias Atrium.Tenants.Provisioner

  setup do
    slug = "cc_#{:erlang.unique_integer([:positive])}"
    host = "#{slug}.atrium.example"
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: slug, name: "Customer Ctrl Test"})
    {:ok, _} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop(slug) end)
    prefix = Triplex.to_prefix(slug)

    {:ok, %{user: editor}} = Accounts.invite_user(prefix, %{
      email: "editor_#{System.unique_integer([:positive])}@example.com",
      name: "Editor"
    })
    {:ok, editor} = Accounts.activate_user_with_password(prefix, editor, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "customers", {:user, editor.id}, :view)
    Authorization.grant_section(prefix, "customers", {:user, editor.id}, :edit)

    {:ok, %{user: outsider}} = Accounts.invite_user(prefix, %{
      email: "outsider_#{System.unique_integer([:positive])}@example.com",
      name: "Outsider"
    })
    {:ok, outsider} = Accounts.activate_user_with_password(prefix, outsider, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })

    {:ok, %{user: viewer}} = Accounts.invite_user(prefix, %{
      email: "viewer_#{System.unique_integer([:positive])}@example.com",
      name: "Viewer"
    })
    {:ok, viewer} = Accounts.activate_user_with_password(prefix, viewer, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "customers", {:user, viewer.id}, :view)

    editor_conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: editor.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    outsider_conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: outsider.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    viewer_conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: viewer.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    {:ok, editor_conn: editor_conn, outsider_conn: outsider_conn, viewer_conn: viewer_conn, prefix: prefix}
  end

  test "GET /customers shows index to authorized user", %{editor_conn: conn} do
    conn = get(conn, "/customers")
    assert html_response(conn, 200) =~ "Customers"
  end

  test "GET /customers is forbidden for unauthorized user", %{outsider_conn: conn} do
    conn = get(conn, "/customers")
    assert conn.status == 403
  end

  test "GET /customers/:id shows a customer and its people", %{editor_conn: conn, prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    {:ok, _} = Customers.add_person(prefix, c.id, %{"name" => "Bob Vance"})

    conn = get(conn, "/customers/#{c.id}")
    body = html_response(conn, 200)
    assert body =~ "Acme Co"
    assert body =~ "Bob Vance"
  end

  test "GET /customers/:id is forbidden for unauthorized user", %{outsider_conn: conn, prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    conn = get(conn, "/customers/#{c.id}")
    assert conn.status == 403
  end

  test "view-only user sees the customer but not edit controls", %{viewer_conn: conn, prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    conn = get(conn, "/customers/#{c.id}")
    body = html_response(conn, 200)
    assert body =~ "Acme Co"
    refute body =~ "Add a person"
  end

  test "POST /customers creates a customer", %{editor_conn: conn} do
    conn = post(conn, "/customers", %{customer: %{name: "New Co", website: "new.co"}})
    assert redirected_to(conn) =~ "/customers/"
  end

  test "PUT /customers/:id updates a customer", %{editor_conn: conn, prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Old Name"})
    conn = put(conn, "/customers/#{c.id}", %{customer: %{name: "New Name"}})
    assert redirected_to(conn) == "/customers/#{c.id}"
    assert Customers.get_customer!(prefix, c.id).name == "New Name"
  end

  test "DELETE /customers/:id deletes a customer", %{editor_conn: conn, prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    conn = delete(conn, "/customers/#{c.id}")
    assert redirected_to(conn) == "/customers"
    assert Customers.list_customers(prefix) == []
  end

  test "POST /customers is forbidden for unauthorized user", %{outsider_conn: conn} do
    conn = post(conn, "/customers", %{customer: %{name: "Nope"}})
    assert conn.status == 403
  end
end
