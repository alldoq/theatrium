defmodule Atrium.Accounts.Idp do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Accounts.IdpConfiguration
  alias Atrium.Audit

  def create_idp(prefix, attrs) do
    with {:ok, idp} <- %IdpConfiguration{}
                       |> IdpConfiguration.create_changeset(attrs)
                       |> Repo.insert(prefix: prefix) do
      {:ok, _} = Audit.log(prefix, "idp.created", %{
        actor: :system,
        resource: {"IdpConfiguration", idp.id},
        changes: Audit.changeset_diff(%IdpConfiguration{}, idp)
      })
      {:ok, idp}
    end
  end

  def update_idp(prefix, old_idp, attrs) do
    with {:ok, idp} <- old_idp
                       |> IdpConfiguration.update_changeset(attrs)
                       |> Repo.update(prefix: prefix) do
      {:ok, _} = Audit.log(prefix, "idp.updated", %{
        actor: :system,
        resource: {"IdpConfiguration", idp.id},
        changes: Audit.changeset_diff(old_idp, idp)
      })
      {:ok, idp}
    end
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

  def delete_idp(prefix, idp) do
    with {:ok, deleted} <- Repo.delete(idp, prefix: prefix) do
      {:ok, _} = Audit.log(prefix, "idp.deleted", %{
        actor: :system,
        resource: {"IdpConfiguration", deleted.id}
      })
      {:ok, deleted}
    end
  end
end
