defmodule Atrium.Accounts.SessionSweeper do
  use Oban.Worker, queue: :maintenance, unique: [period: 600]

  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Accounts.Session

  @impl Oban.Worker
  def perform(_job) do
    Atrium.Tenants.list_active_tenants()
    |> Enum.each(fn tenant -> sweep(Triplex.to_prefix(tenant.slug)) end)

    :ok
  end

  @spec sweep(String.t()) :: {:ok, non_neg_integer()}
  def sweep(prefix) do
    now = DateTime.utc_now()
    {count, _} = Repo.delete_all(from(s in Session, where: s.expires_at < ^now), prefix: prefix)
    {:ok, count}
  end
end
