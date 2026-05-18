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

    {:ok, editor_conn: editor_conn, outsider_conn: outsider_conn, viewer_conn: viewer_conn, prefix: prefix, user: editor}
  end

  test "GET /customers shows index to authorized user", %{editor_conn: conn} do
    conn = get(conn, "/customers")
    assert html_response(conn, 200) =~ "Customers"
  end

  test "GET /customers is forbidden for unauthorized user", %{outsider_conn: conn} do
    conn = get(conn, "/customers")
    assert conn.status == 403
  end

  test "GET /customers/:id shows a customer and its people", %{editor_conn: conn, prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    {:ok, _} = Customers.add_person(prefix, c.id, %{"name" => "Bob Vance"}, user)

    conn = get(conn, "/customers/#{c.id}")
    body = html_response(conn, 200)
    assert body =~ "Acme Co"
    assert body =~ "Bob Vance"
  end

  test "GET /customers/:id is forbidden for unauthorized user", %{outsider_conn: conn, prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    conn = get(conn, "/customers/#{c.id}")
    assert conn.status == 403
  end

  test "view-only user sees the customer but not edit controls", %{viewer_conn: conn, prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    conn = get(conn, "/customers/#{c.id}")
    body = html_response(conn, 200)
    assert body =~ "Acme Co"
    refute body =~ "Add a person"
  end

  test "POST /customers creates a customer", %{editor_conn: conn} do
    conn = post(conn, "/customers", %{customer: %{name: "New Co", website: "new.co"}})
    assert redirected_to(conn) =~ "/customers/"
  end

  test "PUT /customers/:id updates a customer", %{editor_conn: conn, prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Old Name"}, user)
    conn = put(conn, "/customers/#{c.id}", %{customer: %{name: "New Name"}})
    assert redirected_to(conn) == "/customers/#{c.id}"
    assert Customers.get_customer!(prefix, c.id).name == "New Name"
  end

  test "DELETE /customers/:id deletes a customer", %{editor_conn: conn, prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    conn = delete(conn, "/customers/#{c.id}")
    assert redirected_to(conn) == "/customers"
    assert Customers.list_customers(prefix) == []
  end

  test "POST /customers is forbidden for unauthorized user", %{outsider_conn: conn} do
    conn = post(conn, "/customers", %{customer: %{name: "Nope"}})
    assert conn.status == 403
  end

  test "POST /customers with invalid params re-renders the form", %{editor_conn: conn} do
    conn = post(conn, "/customers", %{customer: %{name: ""}})
    assert conn.status == 200
    assert html_response(conn, 200) =~ "New customer"
  end

  test "PUT /customers/:id with invalid params re-renders the form", %{editor_conn: conn, prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    conn = put(conn, "/customers/#{c.id}", %{customer: %{name: ""}})
    assert conn.status == 200
    assert html_response(conn, 200) =~ "Edit customer"
  end

  test "DELETE /customers/:id is forbidden for unauthorized user", %{outsider_conn: conn, editor_conn: _ed, prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    conn = delete(conn, "/customers/#{c.id}")
    assert conn.status == 403
  end

  test "PUT /customers/:id is forbidden for unauthorized user", %{outsider_conn: conn, prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    conn = put(conn, "/customers/#{c.id}", %{customer: %{name: "X"}})
    assert conn.status == 403
  end

  test "POST /customers/:id/people adds a person", %{editor_conn: conn, prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    conn = post(conn, "/customers/#{c.id}/people", %{person: %{name: "Bob"}})
    assert redirected_to(conn) == "/customers/#{c.id}"
    assert [%{name: "Bob"}] = Customers.get_customer!(prefix, c.id).people
  end

  test "PUT person updates the person", %{editor_conn: conn, prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    {:ok, p} = Customers.add_person(prefix, c.id, %{"name" => "Bob"}, user)
    conn = put(conn, "/customers/#{c.id}/people/#{p.id}", %{person: %{job_title: "CEO"}})
    assert redirected_to(conn) == "/customers/#{c.id}"
    assert Customers.get_person!(prefix, c.id, p.id).job_title == "CEO"
  end

  test "DELETE person removes the person", %{editor_conn: conn, prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    {:ok, p} = Customers.add_person(prefix, c.id, %{"name" => "Bob"}, user)
    conn = delete(conn, "/customers/#{c.id}/people/#{p.id}")
    assert redirected_to(conn) == "/customers/#{c.id}"
    assert Customers.get_customer!(prefix, c.id).people == []
  end

  test "person actions reject a pid from a different customer", %{editor_conn: conn, prefix: prefix, user: user} do
    {:ok, c1} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    {:ok, c2} = Customers.create_customer(prefix, %{"name" => "Globex"}, user)
    {:ok, p} = Customers.add_person(prefix, c1.id, %{"name" => "Bob"}, user)

    assert_error_sent 404, fn ->
      delete(conn, "/customers/#{c2.id}/people/#{p.id}")
    end
  end

  test "POST /customers/:id/people is forbidden for unauthorized user", %{outsider_conn: conn, prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    conn = post(conn, "/customers/#{c.id}/people", %{person: %{name: "Bob"}})
    assert conn.status == 403
  end

  test "GET edit_person renders the person form", %{editor_conn: conn, prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    {:ok, p} = Customers.add_person(prefix, c.id, %{"name" => "Bob Vance"}, user)
    conn = get(conn, "/customers/#{c.id}/people/#{p.id}/edit")
    assert html_response(conn, 200) =~ "Bob Vance"
  end

  test "GET edit_person rejects a pid from a different customer", %{editor_conn: conn, prefix: prefix, user: user} do
    {:ok, c1} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    {:ok, c2} = Customers.create_customer(prefix, %{"name" => "Globex"}, user)
    {:ok, p} = Customers.add_person(prefix, c1.id, %{"name" => "Bob"}, user)

    assert_error_sent 404, fn ->
      get(conn, "/customers/#{c2.id}/people/#{p.id}/edit")
    end
  end

  test "GET edit_person is forbidden for unauthorized user", %{outsider_conn: conn, prefix: prefix, user: user} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"}, user)
    {:ok, p} = Customers.add_person(prefix, c.id, %{"name" => "Bob"}, user)
    conn = get(conn, "/customers/#{c.id}/people/#{p.id}/edit")
    assert conn.status == 403
  end
end
