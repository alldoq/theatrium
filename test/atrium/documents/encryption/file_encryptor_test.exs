defmodule Atrium.Documents.Encryption.FileEncryptorTest do
  use ExUnit.Case, async: true
  alias Atrium.Documents.Encryption.FileEncryptor

  @tmp Path.join(System.tmp_dir!(), "atrium_enc_test")

  setup do
    File.mkdir_p!(@tmp)
    on_exit(fn -> File.rm_rf!(@tmp) end)
    :ok
  end

  test "encrypts a small file and reports metadata" do
    source = Path.join(@tmp, "plain.txt")
    dest = Path.join(@tmp, "out.enc")
    content = "hello world " |> String.duplicate(1000)
    File.write!(source, content)

    key = :crypto.strong_rand_bytes(32)
    iv = :crypto.strong_rand_bytes(12)

    {:ok, meta} = FileEncryptor.call(source, dest, key, iv)

    assert byte_size(meta.auth_tag) == 16
    assert meta.byte_size == byte_size(content)
    assert String.length(meta.sha256) == 64

    # Dest is not the plaintext
    assert File.read!(dest) != content
  end

  test "encrypts a multi-chunk file (>64 KB)" do
    source = Path.join(@tmp, "big.bin")
    dest = Path.join(@tmp, "big.enc")
    content = :crypto.strong_rand_bytes(200_000)
    File.write!(source, content)

    key = :crypto.strong_rand_bytes(32)
    iv = :crypto.strong_rand_bytes(12)

    {:ok, meta} = FileEncryptor.call(source, dest, key, iv)
    assert meta.byte_size == 200_000
    assert byte_size(File.read!(dest)) > 0
  end
end
