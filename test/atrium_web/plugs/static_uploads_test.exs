defmodule AtriumWeb.Plugs.StaticUploadsTest do
  use AtriumWeb.ConnCase, async: false
  alias AtriumWeb.Plugs.StaticUploads

  @uploads "tmp/test_uploads"

  setup do
    File.mkdir_p!(Path.join([@uploads, "documents", "t1", "images"]))
    File.mkdir_p!(Path.join([@uploads, "documents", "t1", "files", "doc1"]))
    File.write!(Path.join([@uploads, "documents", "t1", "images", "pic.png"]), "img-bytes")
    File.write!(Path.join([@uploads, "documents", "t1", "files", "doc1", "v1.enc"]), "ciphertext")

    on_exit(fn ->
      File.rm_rf!(Path.join([@uploads, "documents", "t1"]))
    end)

    :ok
  end

  test "404s a request under /uploads/documents/*/files/*", %{conn: conn} do
    conn =
      conn
      |> Map.put(:request_path, "/uploads/documents/t1/files/doc1/v1.enc")
      |> Map.put(:path_info, ~w(uploads documents t1 files doc1 v1.enc))
      |> StaticUploads.call(StaticUploads.init([]))

    assert conn.status == 404
    assert conn.halted
  end

  test "404s an arbitrary /uploads path not in images/", %{conn: conn} do
    conn =
      conn
      |> Map.put(:request_path, "/uploads/secret.txt")
      |> Map.put(:path_info, ~w(uploads secret.txt))
      |> StaticUploads.call(StaticUploads.init([]))

    assert conn.status == 404
    assert conn.halted
  end

  test "passes an images path through to Plug.Static", %{conn: conn} do
    # Plug.Static will either serve the file (200) or pass through. The assertion
    # is: the request is NOT halted with a 404 by our guard.
    conn =
      conn
      |> Map.put(:request_path, "/uploads/documents/t1/images/pic.png")
      |> Map.put(:path_info, ~w(uploads documents t1 images pic.png))
      |> StaticUploads.call(StaticUploads.init([]))

    refute conn.status == 404 and conn.halted
  end
end
