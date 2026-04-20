defmodule Atrium.Documents.Encryption.Processor do
  @moduledoc """
  High-level orchestrator for file encryption / decryption.

  - encrypt_upload/2 takes a %Plug.Upload{} and a destination absolute path.
    Returns {:ok, meta} where meta contains all the fields needed to insert
    a %DocumentFile{}: wrapped_key, iv, auth_tag, byte_size, sha256.

  - decrypt_to_temp/1 accepts a map with keys storage_path_abs, wrapped_key,
    iv, auth_tag and writes plaintext to a tmp file. Returns {:ok, tmp_path}.
    Caller must remove the tmp file after use.
  """

  alias Atrium.Documents.Encryption.{DataKey, FileEncryptor, FileDecryptor}

  def encrypt_upload(%Plug.Upload{path: src_path}, dest_path) when is_binary(dest_path) do
    {key, iv} = DataKey.generate()

    with {:ok, meta} <- FileEncryptor.call(src_path, dest_path, key, iv) do
      {:ok,
       %{
         wrapped_key: DataKey.wrap(key),
         iv: iv,
         auth_tag: meta.auth_tag,
         byte_size: meta.byte_size,
         sha256: meta.sha256
       }}
    end
  end

  def decrypt_to_temp(%{
        storage_path_abs: src,
        wrapped_key: wrapped,
        iv: iv,
        auth_tag: tag
      }) do
    key = DataKey.unwrap(wrapped)
    tmp = Path.join(System.tmp_dir!(), "atrium_dl_#{System.unique_integer([:positive])}")

    case FileDecryptor.call(src, tmp, key, iv, tag) do
      {:ok, _size} -> {:ok, tmp}
      {:error, reason} -> {:error, reason}
    end
  end
end
