defmodule Atrium.Audit do
  @moduledoc """
  Append-only audit logging.

  Phase 0a exposes `log_global/2` and `list_global/1` for public-schema events.
  Tenant-scoped `log/2` and `list/1` are added in plan 0e.
  """
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Audit.GlobalEvent
  alias Atrium.Audit.Event

  @type actor ::
          :system
          | {:super_admin, Ecto.UUID.t()}
          | {:user, Ecto.UUID.t()}

  @spec log_global(String.t(), map()) :: {:ok, GlobalEvent.t()} | {:error, Ecto.Changeset.t()}
  def log_global(action, opts) when is_binary(action) do
    {actor_type, actor_id} = decode_actor(Map.get(opts, :actor, :system))
    {resource_type, resource_id} = decode_resource(Map.get(opts, :resource))

    attrs = %{
      actor_type: actor_type,
      actor_id: actor_id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      changes: stringify_keys(Map.get(opts, :changes, %{})),
      context: stringify_keys(Map.get(opts, :context, %{})),
      occurred_at: DateTime.utc_now()
    }

    %GlobalEvent{}
    |> GlobalEvent.changeset(attrs)
    |> Repo.insert()
  end

  def log_global(nil, _opts), do: raise(ArgumentError, "action is required")

  @spec list_global(keyword()) :: [GlobalEvent.t()]
  def list_global(filters \\ []) do
    query = from e in GlobalEvent, order_by: [desc: e.occurred_at]

    Enum.reduce(filters, query, fn
      {:action, action}, q -> where(q, [e], e.action == ^action)
      {:actor_id, id}, q -> where(q, [e], e.actor_id == ^id)
      {:resource_type, t}, q -> where(q, [e], e.resource_type == ^t)
      {:resource_id, id}, q -> where(q, [e], e.resource_id == ^id)
      {:limit, n}, q -> limit(q, ^n)
      _, q -> q
    end)
    |> Repo.all()
  end

  @spec log(String.t(), String.t(), map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def log(prefix, action, opts) when is_binary(prefix) and is_binary(action) do
    {actor_type, actor_id} = decode_actor(Map.get(opts, :actor, :system))
    {resource_type, resource_id} = decode_resource(Map.get(opts, :resource))

    attrs = %{
      actor_type: actor_type,
      actor_id: actor_id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      changes: stringify_keys(Map.get(opts, :changes, %{})),
      context: stringify_keys(Map.get(opts, :context, %{})),
      occurred_at: DateTime.utc_now()
    }

    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert(prefix: prefix)
  end

  @spec list(String.t(), keyword()) :: [Event.t()]
  def list(prefix, filters \\ []) do
    query = from e in Event, order_by: [desc: e.occurred_at]

    query =
      Enum.reduce(filters, query, fn
        {:action, action}, q -> where(q, [e], e.action == ^action)
        {:actor_id, id}, q -> where(q, [e], e.actor_id == ^id)
        {:resource_type, t}, q -> where(q, [e], e.resource_type == ^t)
        {:resource_id, id}, q -> where(q, [e], e.resource_id == ^id)
        {:from, dt}, q -> where(q, [e], e.occurred_at >= ^dt)
        {:to, dt}, q -> where(q, [e], e.occurred_at <= ^dt)
        {:limit, n}, q -> limit(q, ^n)
        _, q -> q
      end)

    Repo.all(query, prefix: prefix)
  end

  @spec history_for(String.t(), String.t(), String.t()) :: [Event.t()]
  def history_for(prefix, resource_type, resource_id) do
    list(prefix, resource_type: resource_type, resource_id: to_string(resource_id))
  end

  @spec changeset_diff(Ecto.Schema.t() | map(), Ecto.Schema.t() | map(), keyword()) :: map()
  def changeset_diff(old, new, opts \\ []) do
    redactions = opts[:redactions] || discover_redactions(new, old)

    old_map = schema_to_map(old)
    new_map = schema_to_map(new)

    keys = MapSet.union(MapSet.new(Map.keys(old_map)), MapSet.new(Map.keys(new_map)))

    Enum.reduce(keys, %{}, fn key, acc ->
      skey = to_string(key)
      o = Map.get(old_map, key)
      n = Map.get(new_map, key)

      cond do
        key in redactions ->
          Map.put(acc, skey, ["[REDACTED]", "[REDACTED]"])

        o != n ->
          Map.put(acc, skey, [o, n])

        true ->
          acc
      end
    end)
  end

  defp discover_redactions(%_{} = struct, _), do: Atrium.Audit.Redactable.redactions(struct)
  defp discover_redactions(_, %_{} = struct), do: Atrium.Audit.Redactable.redactions(struct)
  defp discover_redactions(_, _), do: []

  defp schema_to_map(%_{} = struct) do
    struct |> Map.from_struct() |> Map.drop([:__meta__, :__struct__])
  end

  defp schema_to_map(map) when is_map(map), do: map

  defp decode_actor(:system), do: {"system", nil}
  defp decode_actor({:super_admin, id}) when is_binary(id), do: {"super_admin", id}
  defp decode_actor({:user, id}) when is_binary(id), do: {"user", id}

  defp decode_resource(nil), do: {nil, nil}
  defp decode_resource({type, id}) when is_binary(type), do: {type, to_string(id)}

  defp stringify_keys(map) when is_map(map) do
    for {k, v} <- map, into: %{}, do: {to_string(k), stringify_keys(v)}
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other
end
