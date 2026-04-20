defmodule AtriumWeb.Plugs.StaticUploads do
  @moduledoc """
  Serves static uploads under /uploads, but ONLY paths of the form
  /uploads/documents/<tenant>/images/<filename>.

  Any other path (e.g. /uploads/documents/<tenant>/files/...) is 404'd
  before it can hit the filesystem — encrypted files must go through the
  authenticated download controller.
  """

  @behaviour Plug

  @uploads_root Application.compile_env(:atrium, :uploads_root, "priv/uploads")

  @impl true
  def init(_opts) do
    Plug.Static.init(
      at: "/uploads",
      from: @uploads_root,
      gzip: false
    )
  end

  @impl true
  def call(conn, static_opts) do
    cond do
      not uploads_path?(conn.path_info) ->
        conn

      images_path?(conn.path_info) ->
        Plug.Static.call(conn, static_opts)

      true ->
        conn
        |> Plug.Conn.send_resp(404, "Not found")
        |> Plug.Conn.halt()
    end
  end

  defp uploads_path?(["uploads" | _]), do: true
  defp uploads_path?(_), do: false

  defp images_path?(["uploads", "documents", _tenant, "images" | _]), do: true
  defp images_path?(_), do: false
end
