defmodule Atrium.Documents.Encryption.FileDecryptor do
  @moduledoc """
  Decrypts a ciphertext file → plaintext file using AES-256-GCM (one-shot).
  Verifies the auth tag; returns {:error, :auth_failed} on mismatch.
  """

  @aad ""

  def call(source_path, dest_path, key, iv, auth_tag)
      when is_binary(key) and byte_size(key) == 32 and
             is_binary(iv) and byte_size(iv) == 12 and
             is_binary(auth_tag) and byte_size(auth_tag) == 16 do
    File.mkdir_p!(Path.dirname(dest_path))

    try do
      ciphertext = File.read!(source_path)

      case :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             key,
             iv,
             ciphertext,
             @aad,
             auth_tag,
             false
           ) do
        plaintext when is_binary(plaintext) ->
          File.write!(dest_path, plaintext)
          {:ok, byte_size(plaintext)}

        :error ->
          _ = File.rm(dest_path)
          {:error, :auth_failed}
      end
    rescue
      _e ->
        _ = File.rm(dest_path)
        {:error, :auth_failed}
    end
  end
end
