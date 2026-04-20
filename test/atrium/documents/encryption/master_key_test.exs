defmodule Atrium.Documents.Encryption.MasterKeyTest do
  use ExUnit.Case, async: false
  alias Atrium.Documents.Encryption.MasterKey

  test "get/0 returns the configured 32-byte key" do
    key = MasterKey.get()
    assert is_binary(key)
    assert byte_size(key) == 32
    assert key == Application.fetch_env!(:atrium, :file_encryption_key)
  end

  test "get/0 is idempotent (caches)" do
    k1 = MasterKey.get()
    k2 = MasterKey.get()
    assert k1 == k2
  end
end
