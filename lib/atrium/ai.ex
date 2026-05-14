defmodule Atrium.AI do
  @moduledoc """
  Thin wrapper around the Anthropic Messages API.

  Sends a single message + optional system prompt with intranet search
  context. Streaming is not used; we return the full text response.
  """

  require Logger

  @endpoint "https://api.anthropic.com/v1/messages"
  @model "claude-haiku-4-5-20251001"
  @max_tokens 1024
  @anthropic_version "2023-06-01"

  def enabled? do
    case api_key() do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  def ask(prefix, user, question, opts \\ []) do
    history = Keyword.get(opts, :history, [])
    context = build_context(prefix, user, question)
    system = system_prompt(user, context)

    messages =
      history ++ [%{role: "user", content: question}]

    payload = %{
      model: @model,
      max_tokens: @max_tokens,
      system: system,
      messages: messages
    }

    case Req.post(@endpoint,
           json: payload,
           headers: [
             {"x-api-key", api_key()},
             {"anthropic-version", @anthropic_version}
           ],
           receive_timeout: 30_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"content" => parts}}} ->
        text =
          parts
          |> Enum.filter(&(&1["type"] == "text"))
          |> Enum.map_join("", & &1["text"])

        {:ok, text, context}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Anthropic error #{status}: #{inspect(body)}")
        {:error, "AI request failed (HTTP #{status})"}

      {:error, reason} ->
        Logger.error("Anthropic transport error: #{inspect(reason)}")
        {:error, "AI request failed (network)"}
    end
  end

  defp api_key, do: System.get_env("ANTHROPIC_API_KEY") || Application.get_env(:atrium, :anthropic_api_key)

  defp build_context(prefix, user, question) do
    Atrium.Search.global_search(prefix, user, question, limit: 3)
  end

  defp system_prompt(user, context) do
    base = """
    You are the AI assistant for the Atrium intranet at this company. Help
    staff find information from the intranet. Answer concisely. If the user
    asks something you cannot answer from the supplied context, say so and
    suggest where they might look or who to contact.

    The current user is: #{user.name} (#{user.email}).
    """

    if context == [] do
      base <> "\nNo intranet content matched the question."
    else
      formatted =
        context
        |> Enum.map(fn r ->
          "- [#{r.section}] #{r.title} (#{r.path}) — #{r.snippet}"
        end)
        |> Enum.join("\n")

      base <>
        "\nRelevant intranet content (use it when answering, and cite by name):\n" <>
        formatted
    end
  end
end
