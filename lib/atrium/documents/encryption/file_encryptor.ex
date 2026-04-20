defmodule Atrium.Documents.Encryption.FileEncryptor do
  @moduledoc """
  Encrypts a plaintext file → ciphertext file using AES-256-GCM (one-shot).
  Returns {:ok, %{auth_tag, byte_size, sha256}} on success.

  Note: uses `:crypto.crypto_one_time_aead/6` because the streaming
  `:crypto.crypto_init/4` + `:crypto.crypto_get_tag/2` API does not
  expose GCM tag extraction on this OTP build. Loads the full file
  into memory — acceptable given the 100 MB upload cap enforced
  elsewhere in the product.
  """

  @aad ""

  def call(source_path, dest_path, key, iv)
      when is_binary(key) and byte_size(key) == 32 and
             is_binary(iv) and byte_size(iv) == 12 do
    File.mkdir_p!(Path.dirname(dest_path))

    try do
      plaintext = File.read!(source_path)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, true)

      File.write!(dest_path, ciphertext)

      {:ok,
       %{
         auth_tag: tag,
         byte_size: byte_size(plaintext),
         sha256: :crypto.hash(:sha256, plaintext) |> Base.encode16(case: :lower)
       }}
    rescue
      e ->
        _ = File.rm(dest_path)
        {:error, Exception.message(e)}
    end
  end
end
