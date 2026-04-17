defmodule Atrium.SuperAdmins do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.SuperAdmins.SuperAdmin

  @spec create_super_admin(map()) :: {:ok, SuperAdmin.t()} | {:error, Ecto.Changeset.t()}
  def create_super_admin(attrs) do
    %SuperAdmin{}
    |> SuperAdmin.create_changeset(attrs)
    |> Repo.insert()
  end

  @spec get_super_admin!(Ecto.UUID.t()) :: SuperAdmin.t()
  def get_super_admin!(id), do: Repo.get!(SuperAdmin, id)

  @spec get_super_admin(Ecto.UUID.t()) :: SuperAdmin.t() | nil
  def get_super_admin(id), do: Repo.get(SuperAdmin, id)

  @spec authenticate(String.t(), String.t()) ::
          {:ok, SuperAdmin.t()} | {:error, :invalid_credentials | :suspended}
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    sa = Repo.one(from s in SuperAdmin, where: s.email == ^email)

    cond do
      is_nil(sa) ->
        Argon2.no_user_verify()
        {:error, :invalid_credentials}

      not Argon2.verify_pass(password, sa.hashed_password) ->
        {:error, :invalid_credentials}

      sa.status != "active" ->
        {:error, :suspended}

      true ->
        {:ok, record_login!(sa)}
    end
  end

  def update_status(%SuperAdmin{} = sa, status) do
    sa |> SuperAdmin.status_changeset(status) |> Repo.update()
  end

  defp record_login!(sa) do
    sa |> SuperAdmin.last_login_changeset(DateTime.utc_now()) |> Repo.update!()
  end
end
