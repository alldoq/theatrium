defmodule Atrium.Accounts do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Accounts.{User, UserIdentity, Session, InvitationToken, PasswordResetToken}

  @invitation_ttl_hours 72
  @password_reset_ttl_minutes 60
  @default_session_ttl_minutes 480

  # -- Invitations -----------------------------------------------------------

  def invite_user(prefix, attrs) do
    Repo.transaction(fn ->
      with {:ok, user} <- insert_invited_user(prefix, attrs),
           {raw, hash} = token_pair(),
           {:ok, _} <- insert_invitation_token(prefix, user, hash) do
        %{user: user, token: raw}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def activate_user(prefix, raw_token, password) do
    hash = hash_token(raw_token)

    Repo.transaction(fn ->
      case fetch_usable_token(prefix, InvitationToken, hash) do
        {:ok, token} ->
          user = Repo.get!(User, token.user_id, prefix: prefix)
          changeset = User.activate_password_changeset(user, %{password: password})

          with {:ok, user} <- Repo.update(changeset, prefix: prefix),
               {:ok, _} <- mark_token_used(prefix, token),
               {:ok, _} <- upsert_local_identity(prefix, user) do
            user
          else
            {:error, reason} -> Repo.rollback(reason)
          end

        :error ->
          Repo.rollback(:invalid_or_expired_token)
      end
    end)
  end

  # -- Authentication --------------------------------------------------------

  def authenticate_by_password(prefix, email, password) do
    user = Repo.one(from(u in User, where: u.email == ^email), prefix: prefix)

    cond do
      is_nil(user) ->
        Argon2.no_user_verify()
        {:error, :invalid_credentials}

      is_nil(user.hashed_password) ->
        {:error, :invalid_credentials}

      not Argon2.verify_pass(password, user.hashed_password) ->
        {:error, :invalid_credentials}

      user.status != "active" ->
        {:error, :suspended}

      true ->
        {:ok, record_login!(prefix, user)}
    end
  end

  # -- Sessions --------------------------------------------------------------

  def create_session(prefix, %User{} = user, metadata, opts \\ []) do
    ttl = Keyword.get(opts, :ttl_minutes, @default_session_ttl_minutes)
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, ttl * 60, :second)
    {raw, hash} = token_pair()

    attrs = %{
      user_id: user.id,
      token_hash: hash,
      expires_at: expires_at,
      last_seen_at: now,
      ip: Map.get(metadata, :ip),
      user_agent: Map.get(metadata, :user_agent)
    }

    {:ok, session} = Session.new_changeset(attrs) |> Repo.insert(prefix: prefix)
    {:ok, %{session: session, token: raw}}
  end

  def get_session_by_token(prefix, raw_token) do
    hash = hash_token(raw_token)

    case Repo.get_by(Session, [token_hash: hash], prefix: prefix) do
      nil ->
        :not_found

      session ->
        if DateTime.compare(session.expires_at, DateTime.utc_now()) == :lt do
          :expired
        else
          user = Repo.get!(User, session.user_id, prefix: prefix)
          touched = session |> Session.touch_changeset(DateTime.utc_now()) |> Repo.update!(prefix: prefix)
          {:ok, %{session: touched, user: user}}
        end
    end
  end

  def revoke_session(prefix, raw_token) do
    hash = hash_token(raw_token)

    case Repo.get_by(Session, [token_hash: hash], prefix: prefix) do
      nil ->
        :not_found

      session ->
        case Repo.delete(session, prefix: prefix) do
          {:ok, _} -> :ok
          {:error, _} -> :not_found
        end
    end
  end

  def revoke_all_sessions_for_user(prefix, %User{id: id}) do
    {count, _} = Repo.delete_all(from(s in Session, where: s.user_id == ^id), prefix: prefix)
    {:ok, count}
  end

  # -- Password reset --------------------------------------------------------

  def request_password_reset(prefix, email) do
    case Repo.one(from(u in User, where: u.email == ^email), prefix: prefix) do
      nil ->
        {:ok, :maybe_sent}

      %User{status: "active"} = user ->
        {raw, hash} = token_pair()

        {:ok, _} =
          PasswordResetToken.new_changeset(%{
            user_id: user.id,
            token_hash: hash,
            expires_at: DateTime.add(DateTime.utc_now(), @password_reset_ttl_minutes * 60, :second)
          })
          |> Repo.insert(prefix: prefix)

        {:ok, %{token: raw, user: user}}

      _ ->
        {:ok, :maybe_sent}
    end
  end

  def reset_password(prefix, raw_token, new_password) do
    hash = hash_token(raw_token)

    Repo.transaction(fn ->
      case fetch_usable_token(prefix, PasswordResetToken, hash) do
        {:ok, token} ->
          user = Repo.get!(User, token.user_id, prefix: prefix)

          with {:ok, user} <-
                 user
                 |> User.change_password_changeset(%{password: new_password})
                 |> Repo.update(prefix: prefix),
               {:ok, _} <- mark_token_used(prefix, token),
               {:ok, _} <- revoke_all_sessions_for_user(prefix, user) do
            user
          else
            {:error, reason} -> Repo.rollback(reason)
          end

        :error ->
          Repo.rollback(:invalid_or_expired_token)
      end
    end)
  end

  # -- User lifecycle --------------------------------------------------------

  def suspend_user(prefix, user) do
    user |> User.status_changeset("suspended") |> Repo.update(prefix: prefix)
  end

  def get_user(prefix, id), do: Repo.get(User, id, prefix: prefix)

  def list_users(prefix), do: Repo.all(from(u in User, order_by: [asc: u.email]), prefix: prefix)

  # -- Internal --------------------------------------------------------------

  defp insert_invited_user(prefix, attrs) do
    %User{} |> User.invite_changeset(attrs) |> Repo.insert(prefix: prefix)
  end

  defp insert_invitation_token(prefix, user, hash) do
    InvitationToken.new_changeset(%{
      user_id: user.id,
      token_hash: hash,
      expires_at: DateTime.add(DateTime.utc_now(), @invitation_ttl_hours * 3600, :second)
    })
    |> Repo.insert(prefix: prefix)
  end

  defp fetch_usable_token(prefix, schema, hash) do
    case Repo.get_by(schema, [token_hash: hash], prefix: prefix) do
      nil -> :error
      %{used_at: used_at} when not is_nil(used_at) -> :error
      %{expires_at: exp} = row ->
        if DateTime.compare(exp, DateTime.utc_now()) == :gt, do: {:ok, row}, else: :error
    end
  end

  defp mark_token_used(prefix, token) do
    token |> Ecto.Changeset.change(used_at: DateTime.utc_now()) |> Repo.update(prefix: prefix)
  end

  defp upsert_local_identity(prefix, user) do
    %UserIdentity{}
    |> UserIdentity.changeset(%{
      user_id: user.id,
      provider: "local",
      provider_subject: user.id
    })
    |> Repo.insert(prefix: prefix, on_conflict: :nothing, conflict_target: [:provider, :provider_subject])
  end

  defp record_login!(prefix, user) do
    user |> User.last_login_changeset(DateTime.utc_now()) |> Repo.update!(prefix: prefix)
  end

  defp token_pair do
    raw = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    {raw, hash_token(raw)}
  end

  defp hash_token(raw), do: :crypto.hash(:sha256, raw)
end
