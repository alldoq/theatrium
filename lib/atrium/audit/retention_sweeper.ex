defmodule Atrium.Audit.RetentionSweeper do
  @moduledoc """
  Deletes audit_events older than each tenant's audit_retention_days.
  Writes a single summary row per tenant for each purge run.
  """
  use Oban.Worker, queue: :maintenance, unique: [period: 3600]

  import Ecto.Query
  alias Atrium.{Audit, Repo, Tenants}
  alias Atrium.Audit.Event

  @impl Oban.Worker
  def perform(_job) do
    Tenants.list_active_tenants()
    |> Enum.each(fn t ->
      {:ok, _} = sweep(t)
    end)

    :ok
  end

  @spec sweep(Tenants.Tenant.t()) :: {:ok, non_neg_integer()}
  def sweep(tenant) do
    prefix = Triplex.to_prefix(tenant.slug)
    cutoff = DateTime.add(DateTime.utc_now(), -tenant.audit_retention_days * 86_400, :second)

    {count, _} =
      Repo.delete_all(from(e in Event, where: e.occurred_at < ^cutoff), prefix: prefix)

    if count > 0 do
      {:ok, _} =
        Audit.log(prefix, "audit.retention_swept", %{
          actor: :system,
          changes: %{"purged_count" => [0, count], "cutoff" => [nil, DateTime.to_iso8601(cutoff)]}
        })
    end

    {:ok, count}
  end
end
