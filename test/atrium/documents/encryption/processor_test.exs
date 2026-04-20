defmodule Atrium.Documents.Encryption.ProcessorTest do
  use ExUnit.Case, async: true
  alias Atrium.Documents.Encryption.Processor

  @tmp Path.join(System.tmp_dir!(), "atrium_proc_test")

  setup do
    File.mkdir_p!(@tmp)
    on_exit(fn -> File.rm_rf!(@tmp) end)
    :ok
  end

  defp make_upload(content) do
    path = Path.join(@tmp, "upload_#{System.unique_integer([:positive])}.bin")
    File.write!(path, content)
    %Plug.Upload{path: path, filename: "doc.pdf", content_type: "application/pdf"}
  end

  test "encrypt_upload writes ciphertext to dest and returns metadata" do
    content = "some bytes " |> String.duplicate(500)
    upload = make_upload(content)
    dest = Path.join(@tmp, "out.enc")

    {:ok, meta} = Processor.encrypt_upload(upload, dest)

    assert File.exists?(dest)
    assert File.read!(dest) != content
    assert byte_size(meta.wrapped_key) >= 60
    assert byte_size(meta.iv) == 12
    assert byte_size(meta.auth_tag) == 16
    assert meta.byte_size == byte_size(content)
    assert String.length(meta.sha256) == 64
  end

  test "decrypt_to_temp round-trips an encrypted upload" do
    content = :crypto.strong_rand_bytes(50_000)
    upload = make_upload(content)
    dest = Path.join(@tmp, "rt.enc")
    {:ok, meta} = Processor.encrypt_upload(upload, dest)

    df = %{
      storage_path_abs: dest,
      wrapped_key: meta.wrapped_key,
      iv: meta.iv,
      auth_tag: meta.auth_tag
    }

    {:ok, tmp_path} = Processor.decrypt_to_temp(df)
    assert File.read!(tmp_path) == content
    File.rm!(tmp_path)
  end
end
