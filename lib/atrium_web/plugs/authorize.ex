defmodule AtriumWeb.Plugs.Authorize do
  @moduledoc """
  Gates a route on a capability + target pair. Example usage in a controller:

      plug AtriumWeb.Plugs.Authorize, capability: :view, target: {:section, "news"}

  Dynamic targets (e.g. when section comes from a URL param) are supported via
  passing a function: `target: &my_controller_module.target_for/1` that returns
  the target given the conn.
  """
  import Plug.Conn

  alias Atrium.Authorization.Policy

  def init(opts) do
    capability = Keyword.fetch!(opts, :capability)
    target = Keyword.fetch!(opts, :target)
    {capability, target}
  end

  def call(conn, opts) when is_list(opts), do: call(conn, init(opts))

  def call(conn, {capability, target}) do
    resolved_target =
      case target do
        fun when is_function(fun, 1) -> fun.(conn)
        t -> t
      end

    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    if Policy.can?(prefix, user, capability, resolved_target) do
      conn
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(403, "Forbidden")
      |> halt()
    end
  end
end
