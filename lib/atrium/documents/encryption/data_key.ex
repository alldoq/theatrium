defmodule Atrium.Documents.Encryption.DataKey do
  @moduledoc """
  Generates random per-file AES-256-GCM data keys and wraps/unwraps them
  with the master key.

  Wrapped format: <<iv::12 bytes, auth_tag::16 bytes, ciphertext::binary>>.
  """

  alias Atrium.Documents.Encryption.MasterKey

  @iv_bytes 12
  @tag_bytes 16
  @aad ""

  def generate do
    {:crypto.strong_rand_bytes(32), :crypto.strong_rand_bytes(@iv_bytes)}
  end

  def wrap(data_key) when is_binary(data_key) and byte_size(data_key) == 32 do
    iv = :crypto.strong_rand_bytes(@iv_bytes)
    master = MasterKey.get()

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, master, iv, data_key, @aad, true)

    iv <> tag <> ciphertext
  end

  def unwrap(<<iv::binary-size(@iv_bytes), tag::binary-size(@tag_bytes), ciphertext::binary>>) do
    master = MasterKey.get()

    case :crypto.crypto_one_time_aead(:aes_256_gcm, master, iv, ciphertext, @aad, tag, false) do
      plain when is_binary(plain) and byte_size(plain) == 32 -> plain
      :error -> raise "DataKey.unwrap: authentication failed"
    end
  rescue
    e in ErlangError ->
      raise "DataKey.unwrap failed: #{inspect(e)}"
  end
end
