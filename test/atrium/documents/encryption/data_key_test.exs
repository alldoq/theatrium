defmodule Atrium.Documents.Encryption.DataKeyTest do
  use ExUnit.Case, async: true
  alias Atrium.Documents.Encryption.DataKey

  test "generate/0 returns {32-byte key, 12-byte iv}" do
    {key, iv} = DataKey.generate()
    assert byte_size(key) == 32
    assert byte_size(iv) == 12
  end

  test "wrap |> unwrap round-trips" do
    {key, _iv} = DataKey.generate()
    wrapped = DataKey.wrap(key)
    assert DataKey.unwrap(wrapped) == key
  end

  test "wrap produces different ciphertext for same key (fresh IV)" do
    {key, _iv} = DataKey.generate()
    assert DataKey.wrap(key) != DataKey.wrap(key)
  end

  test "unwrap raises on tampered ciphertext" do
    {key, _iv} = DataKey.generate()
    wrapped = DataKey.wrap(key)
    <<head::binary-size(12), tag::binary-size(16), rest::binary>> = wrapped
    tampered =
      head <>
        tag <>
        (rest
         |> :binary.bin_to_list()
         |> Enum.map(&Bitwise.bxor(&1, 1))
         |> :binary.list_to_bin())

    assert_raise RuntimeError, fn -> DataKey.unwrap(tampered) end
  end
end
