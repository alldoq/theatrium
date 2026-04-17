defmodule Atrium.Accounts.Provisioning do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Accounts
  alias Atrium.Accounts.{IdpConfiguration, User, UserIdentity}

  def upsert_from_idp(prefix, %IdpConfiguration{} = idp, claims) do
    subject = Map.fetch!(claims, "sub")
    email = Map.fetch!(claims, "email")
    name = Map.get(claims, "name", email)
    provider = idp.kind

    case Repo.get_by(UserIdentity, [provider: provider, provider_subject: subject], prefix: prefix) do
      %UserIdentity{user_id: uid} ->
        {:ok, Repo.get!(User, uid, prefix: prefix)}

      nil ->
        handle_new_identity(prefix, idp, provider, subject, email, name)
    end
  end

  def confirm_link(prefix, ticket, password) do
    case :ets.lookup(link_tickets_table(), ticket) do
      [] ->
        {:error, :invalid_ticket}

      [{^ticket, %{prefix: ^prefix, user_id: uid, provider: provider, subject: subject, expires_at: exp}}] ->
        if DateTime.compare(exp, DateTime.utc_now()) == :lt do
          :ets.delete(link_tickets_table(), ticket)
          {:error, :invalid_ticket}
        else
          user = Repo.get!(User, uid, prefix: prefix)

          case Accounts.authenticate_by_password(prefix, user.email, password) do
            {:ok, _} ->
              {:ok, _} =
                %UserIdentity{}
                |> UserIdentity.changeset(%{
                  user_id: user.id,
                  provider: provider,
                  provider_subject: subject
                })
                |> Repo.insert(prefix: prefix)

              :ets.delete(link_tickets_table(), ticket)
              {:ok, user}

            {:error, _} ->
              {:error, :invalid_credentials}
          end
        end
    end
  end

  defp handle_new_identity(prefix, %IdpConfiguration{provisioning_mode: "strict"}, provider, subject, email, _name) do
    case find_user_by_email(prefix, email) do
      nil -> {:error, :user_not_found}
      user ->
        {:ok, _} = insert_identity(prefix, user.id, provider, subject)
        {:ok, user}
    end
  end

  defp handle_new_identity(prefix, %IdpConfiguration{provisioning_mode: "auto_create", default_group_ids: gids}, provider, subject, email, name) do
    Repo.transaction(fn ->
      case find_user_by_email(prefix, email) do
        nil ->
          {:ok, user} = Repo.insert(%User{email: email, name: name, status: "active"}, prefix: prefix)
          {:ok, _} = insert_identity(prefix, user.id, provider, subject)
          assign_default_groups(prefix, user, gids)
          user

        user ->
          {:ok, _} = insert_identity(prefix, user.id, provider, subject)
          user
      end
    end)
  end

  defp handle_new_identity(prefix, %IdpConfiguration{provisioning_mode: "link_only"}, provider, subject, email, _name) do
    case find_user_by_email(prefix, email) do
      nil -> {:error, :user_not_found}
      user ->
        ticket = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

        :ets.insert(link_tickets_table(), {ticket, %{
          prefix: prefix,
          user_id: user.id,
          provider: provider,
          subject: subject,
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        }})

        {:needs_password_confirmation, ticket}
    end
  end

  defp find_user_by_email(prefix, email) do
    Repo.one(from(u in User, where: u.email == ^email), prefix: prefix)
  end

  defp insert_identity(prefix, user_id, provider, subject) do
    %UserIdentity{}
    |> UserIdentity.changeset(%{user_id: user_id, provider: provider, provider_subject: subject})
    |> Repo.insert(prefix: prefix)
  end

  defp assign_default_groups(_prefix, _user, []), do: :ok
  defp assign_default_groups(_prefix, _user, _gids), do: :ok

  defp link_tickets_table do
    case :ets.whereis(:atrium_link_tickets) do
      :undefined -> :ets.new(:atrium_link_tickets, [:set, :public, :named_table])
      _tid -> :atrium_link_tickets
    end
  end
end
