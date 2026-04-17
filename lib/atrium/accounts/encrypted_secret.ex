defmodule Atrium.Accounts.EncryptedSecret do
  use Cloak.Ecto.Binary, vault: Atrium.Vault
end
