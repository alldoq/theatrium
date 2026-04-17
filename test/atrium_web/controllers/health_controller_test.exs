defmodule AtriumWeb.HealthControllerTest do
  use AtriumWeb.ConnCase, async: true

  test "GET /healthz returns 200 with JSON status", %{conn: conn} do
    conn = get(Map.put(conn, :host, "admin.atrium.example"), "/healthz")
    assert json_response(conn, 200)["status"] == "ok"
  end
end
