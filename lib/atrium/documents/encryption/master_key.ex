defmodule Atrium.Documents.Encryption.MasterKey do
  @moduledoc """
  Provides the 32-byte master key used to wrap per-file data keys.
  Reads `:atrium, :file_encryption_key` once and caches in :persistent_term.
  """

  @cache_key {__MODULE__, :key}

  def get do
    case :persistent_term.get(@cache_key, :miss) do
      :miss -> load_and_cache()
      key -> key
    end
  end

  defp load_and_cache do
    key = Application.fetch_env!(:atrium, :file_encryption_key)

    cond do
      not is_binary(key) ->
        raise "Atrium file_encryption_key must be a binary; got: #{inspect(key)}"

      byte_size(key) != 32 ->
        raise "Atrium file_encryption_key must be exactly 32 bytes; got #{byte_size(key)}"

      true ->
        :persistent_term.put(@cache_key, key)
        key
    end
  end
end
