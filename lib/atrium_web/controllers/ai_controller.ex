defmodule AtriumWeb.AIController do
  use AtriumWeb, :controller

  def chat(conn, %{"message" => message} = params) when is_binary(message) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    history = Map.get(params, "history", [])

    if not Atrium.AI.enabled?() do
      conn
      |> put_status(503)
      |> json(%{error: "AI assistant is not configured for this tenant."})
    else
      case Atrium.AI.ask(prefix, user, message, history: sanitize_history(history)) do
        {:ok, text, context} ->
          json(conn, %{
            reply: text,
            sources: Enum.map(context, &Map.take(&1, [:title, :path, :section]))
          })

        {:error, msg} ->
          conn |> put_status(502) |> json(%{error: msg})
      end
    end
  end

  def chat(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing message."})
  end

  defp sanitize_history(history) when is_list(history) do
    history
    |> Enum.filter(fn
      %{"role" => r, "content" => c} when r in ["user", "assistant"] and is_binary(c) -> true
      _ -> false
    end)
    |> Enum.map(fn %{"role" => r, "content" => c} -> %{role: r, content: c} end)
    |> Enum.take(-10)
  end

  defp sanitize_history(_), do: []
end
