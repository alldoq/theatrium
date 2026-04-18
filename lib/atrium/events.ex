defmodule Atrium.Events do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Audit
  alias Atrium.Events.Event

  @spec list_events_for_month(String.t(), integer(), integer()) :: [Event.t()]
  def list_events_for_month(prefix, year, month) do
    {:ok, month_start} = Date.new(year, month, 1)
    days_in_month = Date.days_in_month(month_start)
    {:ok, month_end} = Date.new(year, month, days_in_month)

    range_start = DateTime.new!(month_start, ~T[00:00:00.000000], "Etc/UTC")
    range_end = DateTime.new!(month_end, ~T[23:59:59.999999], "Etc/UTC")

    Repo.all(
      from(e in Event,
        where: e.starts_at >= ^range_start and e.starts_at <= ^range_end,
        order_by: [asc: e.starts_at]
      ),
      prefix: prefix
    )
  end

  @spec list_events_for_week(String.t(), Date.t()) :: [Event.t()]
  def list_events_for_week(prefix, week_start) do
    week_end = Date.add(week_start, 6)
    range_start = DateTime.new!(week_start, ~T[00:00:00.000000], "Etc/UTC")
    range_end = DateTime.new!(week_end, ~T[23:59:59.999999], "Etc/UTC")

    Repo.all(
      from(e in Event,
        where: e.starts_at >= ^range_start and e.starts_at <= ^range_end,
        order_by: [asc: e.starts_at]
      ),
      prefix: prefix
    )
  end

  @spec list_events_for_day(String.t(), Date.t()) :: [Event.t()]
  def list_events_for_day(prefix, day) do
    range_start = DateTime.new!(day, ~T[00:00:00.000000], "Etc/UTC")
    range_end = DateTime.new!(day, ~T[23:59:59.999999], "Etc/UTC")

    Repo.all(
      from(e in Event,
        where: e.starts_at >= ^range_start and e.starts_at <= ^range_end,
        order_by: [asc: e.starts_at]
      ),
      prefix: prefix
    )
  end

  @spec list_upcoming_events(String.t(), DateTime.t(), non_neg_integer()) :: [Event.t()]
  def list_upcoming_events(prefix, from_dt \\ nil, limit \\ 10) do
    cutoff = from_dt || DateTime.utc_now()

    Repo.all(
      from(e in Event,
        where: e.starts_at >= ^cutoff,
        order_by: [asc: e.starts_at],
        limit: ^limit
      ),
      prefix: prefix
    )
  end

  @spec get_event!(String.t(), Ecto.UUID.t()) :: Event.t()
  def get_event!(prefix, id), do: Repo.get!(Event, id, prefix: prefix)

  @spec create_event(String.t(), map(), map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def create_event(prefix, attrs, actor_user) do
    attrs_with_author = Map.put(stringify(attrs), "author_id", actor_user.id)

    Repo.transaction(fn ->
      with {:ok, event} <-
             %Event{}
             |> Event.changeset(attrs_with_author)
             |> Repo.insert(prefix: prefix),
           {:ok, _} <-
             Audit.log(prefix, "event.created", %{
               actor: {:user, actor_user.id},
               resource: {"Event", event.id}
             }) do
        event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec update_event(String.t(), Event.t(), map(), map()) ::
          {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def update_event(prefix, %Event{} = event, attrs, actor_user) do
    Repo.transaction(fn ->
      with {:ok, updated} <-
             event
             |> Event.changeset(stringify(attrs))
             |> Repo.update(prefix: prefix),
           {:ok, _} <-
             Audit.log(prefix, "event.updated", %{
               actor: {:user, actor_user.id},
               resource: {"Event", updated.id}
             }) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec delete_event(String.t(), Event.t(), map()) ::
          {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def delete_event(prefix, %Event{} = event, actor_user) do
    Repo.transaction(fn ->
      with {:ok, deleted} <- Repo.delete(event, prefix: prefix),
           {:ok, _} <-
             Audit.log(prefix, "event.deleted", %{
               actor: {:user, actor_user.id},
               resource: {"Event", deleted.id}
             }) do
        deleted
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
end
