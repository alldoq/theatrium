defmodule Atrium.Accounts.Idp do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Accounts.IdpConfiguration

  def create_idp(prefix, attrs) do
    %IdpConfiguration{}
    |> IdpConfiguration.create_changeset(attrs)
    |> Repo.insert(prefix: prefix)
  end

  def update_idp(prefix, idp, attrs) do
    idp
    |> IdpConfiguration.update_changeset(attrs)
    |> Repo.update(prefix: prefix)
  end

  def get_idp!(prefix, id), do: Repo.get!(IdpConfiguration, id, prefix: prefix)

  def list_idps(prefix) do
    Repo.all(from(i in IdpConfiguration, order_by: [desc: i.is_default, asc: i.name]), prefix: prefix)
  end

  def list_enabled(prefix) do
    Repo.all(
      from(i in IdpConfiguration,
        where: i.enabled == true,
        order_by: [desc: i.is_default, asc: i.name]
      ),
      prefix: prefix
    )
  end

  def delete_idp(prefix, idp), do: Repo.delete(idp, prefix: prefix)
end
