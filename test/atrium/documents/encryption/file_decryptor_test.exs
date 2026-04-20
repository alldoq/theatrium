defmodule Atrium.Documents.Encryption.FileDecryptorTest do
  use ExUnit.Case, async: true
  alias Atrium.Documents.Encryption.{FileEncryptor, FileDecryptor}

  @tmp Path.join(System.tmp_dir!(), "atrium_dec_test")

  setup do
    File.mkdir_p!(@tmp)
    on_exit(fn -> File.rm_rf!(@tmp) end)
    :ok
  end

  test "round-trips a random 1 MB file" do
    source = Path.join(@tmp, "r.bin")
    enc = Path.join(@tmp, "r.enc")
    dec = Path.join(@tmp, "r.dec")
    content = :crypto.strong_rand_bytes(1_048_576)
    File.write!(source, content)

    key = :crypto.strong_rand_bytes(32)
    iv = :crypto.strong_rand_bytes(12)

    {:ok, meta} = FileEncryptor.call(source, enc, key, iv)
    {:ok, _size} = FileDecryptor.call(enc, dec, key, iv, meta.auth_tag)

    assert File.read!(dec) == content
  end

  test "returns {:error, :auth_failed} on tampered ciphertext" do
    source = Path.join(@tmp, "t.txt")
    enc = Path.join(@tmp, "t.enc")
    dec = Path.join(@tmp, "t.dec")
    File.write!(source, "secret")

    key = :crypto.strong_rand_bytes(32)
    iv = :crypto.strong_rand_bytes(12)
    {:ok, meta} = FileEncryptor.call(source, enc, key, iv)

    # Flip one bit in the ciphertext
    <<first, rest::binary>> = File.read!(enc)
    File.write!(enc, <<Bitwise.bxor(first, 1), rest::binary>>)

    assert {:error, :auth_failed} = FileDecryptor.call(enc, dec, key, iv, meta.auth_tag)
    refute File.exists?(dec)
  end

  test "returns {:error, :auth_failed} on tampered auth_tag" do
    source = Path.join(@tmp, "t2.txt")
    enc = Path.join(@tmp, "t2.enc")
    dec = Path.join(@tmp, "t2.dec")
    File.write!(source, "secret")

    key = :crypto.strong_rand_bytes(32)
    iv = :crypto.strong_rand_bytes(12)
    {:ok, meta} = FileEncryptor.call(source, enc, key, iv)

    <<b, tag_rest::binary>> = meta.auth_tag
    bad_tag = <<Bitwise.bxor(b, 1), tag_rest::binary>>

    assert {:error, :auth_failed} = FileDecryptor.call(enc, dec, key, iv, bad_tag)
  end
end
