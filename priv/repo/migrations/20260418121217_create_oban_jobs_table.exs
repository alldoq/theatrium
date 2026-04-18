defmodule Atrium.Repo.Migrations.CreateObanJobsTable do
  use Ecto.Migration

  def up, do: Oban.Migration.up(version: 11)
  def down, do: Oban.Migration.down(version: 1)
end
