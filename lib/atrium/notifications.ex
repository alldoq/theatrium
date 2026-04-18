defmodule Atrium.Notifications do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Notifications.Notification

  @spec create(String.t(), binary(), String.t(), map()) ::
          {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  def create(prefix, user_id, type, attrs) do
    params = Map.merge(attrs, %{user_id: user_id, type: type})

    %Notification{}
    |> Notification.create_changeset(params)
    |> Repo.insert(prefix: prefix)
  end

  @spec list_recent(String.t(), binary(), pos_integer()) :: [Notification.t()]
  def list_recent(prefix, user_id, limit \\ 15) do
    from(n in Notification,
      where: n.user_id == ^user_id,
      order_by: [desc: n.inserted_at],
      limit: ^limit
    )
    |> Repo.all(prefix: prefix)
  end

  @spec count_unread(String.t(), binary()) :: non_neg_integer()
  def count_unread(prefix, user_id) do
    from(n in Notification,
      where: n.user_id == ^user_id and is_nil(n.read_at),
      select: count()
    )
    |> Repo.one(prefix: prefix)
  end

  @spec mark_read(String.t(), binary(), binary()) ::
          {:ok, Notification.t()} | {:error, :not_found}
  def mark_read(prefix, user_id, notification_id) do
    case Repo.get_by(Notification, [id: notification_id, user_id: user_id], prefix: prefix) do
      nil ->
        {:error, :not_found}

      notification ->
        notification
        |> Ecto.Changeset.change(read_at: DateTime.utc_now())
        |> Repo.update(prefix: prefix)
    end
  end

  @spec mark_all_read(String.t(), binary()) :: :ok
  def mark_all_read(prefix, user_id) do
    from(n in Notification,
      where: n.user_id == ^user_id and is_nil(n.read_at)
    )
    |> Repo.update_all([set: [read_at: DateTime.utc_now()]], prefix: prefix)

    :ok
  end
end
