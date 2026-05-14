defmodule Atrium.AI do
  @moduledoc """
  AI assistant backed by an OpenAI-compatible chat-completions endpoint
  (Open WebUI / Ollama). Configured via env:

      OLLAMA_ANALYSIS_ENDPOINT  https://ai.alldoq.com
      OLLAMA_ANALYSIS_API_PATH  /api/chat/completions
      OLLAMA_ANALYSIS_API_KEY   <bearer>
      OLLAMA_ANALYSIS_MODEL     nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-FP8
      OLLAMA_ANALYSIS_TIMEOUT   infinity | <ms>

  Each request seeds the system prompt with the top intranet search
  matches the user is allowed to see.
  """

  require Logger

  @default_path "/api/chat/completions"
  @default_model "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-FP8"

  def enabled? do
    case {endpoint(), api_key()} do
      {nil, _} -> false
      {"", _} -> false
      {_, nil} -> false
      {_, ""} -> false
      _ -> true
    end
  end

  def ask(prefix, user, question, opts \\ []) do
    history = Keyword.get(opts, :history, [])
    context = build_context(prefix, user, question)

    messages =
      [%{role: "system", content: system_prompt(user, context)}] ++
        history ++
        [%{role: "user", content: question}]

    payload = %{
      model: model(),
      messages: messages,
      stream: false
    }

    case Req.post(url(),
           json: payload,
           headers: headers(),
           receive_timeout: timeout()
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case extract_text(body) do
          {:ok, text} -> {:ok, text, context}
          :error ->
            Logger.error("AI bad response shape: #{inspect(body)}")
            {:error, "AI replied with unexpected payload"}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("AI error #{status}: #{inspect(body)}")
        {:error, "AI request failed (HTTP #{status})"}

      {:error, reason} ->
        Logger.error("AI transport error: #{inspect(reason)}")
        {:error, "AI request failed (network)"}
    end
  end

  defp extract_text(%{"choices" => [%{"message" => %{"content" => content}} | _]}) when is_binary(content),
    do: {:ok, content}

  defp extract_text(%{"choices" => [%{"text" => content} | _]}) when is_binary(content),
    do: {:ok, content}

  defp extract_text(_), do: :error

  defp endpoint do
    System.get_env("OLLAMA_ANALYSIS_ENDPOINT") ||
      Application.get_env(:atrium, :ai_endpoint)
  end

  defp api_key do
    System.get_env("OLLAMA_ANALYSIS_API_KEY") ||
      Application.get_env(:atrium, :ai_api_key)
  end

  defp api_path do
    (System.get_env("OLLAMA_ANALYSIS_API_PATH") ||
       Application.get_env(:atrium, :ai_api_path) ||
       @default_path)
    |> String.trim()
  end

  defp model do
    System.get_env("OLLAMA_ANALYSIS_MODEL") ||
      Application.get_env(:atrium, :ai_model) ||
      @default_model
  end

  defp timeout do
    case System.get_env("OLLAMA_ANALYSIS_TIMEOUT") do
      nil -> 60_000
      "" -> 60_000
      "infinity" -> :infinity
      other ->
        case Integer.parse(other) do
          {ms, _} -> ms
          :error -> 60_000
        end
    end
  end

  defp url do
    base = endpoint() |> String.trim_trailing("/")
    path = api_path()
    path = if String.starts_with?(path, "/"), do: path, else: "/" <> path
    base <> path
  end

  defp headers do
    [
      {"authorization", "Bearer " <> api_key()},
      {"content-type", "application/json"}
    ]
  end

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
