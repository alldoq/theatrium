defmodule Atrium.Accounts.AllStaff do
  @moduledoc """
  Keeps the `all_staff` group in sync with active users.
  Called from `Accounts` on activate/suspend/restore.
  """
  alias Atrium.Authorization

  @slug "all_staff"

  def ensure_member(prefix, user) do
    case Authorization.get_group_by_slug(prefix, @slug) do
      nil -> :ok
      group -> Authorization.add_member(prefix, user, group)
    end

    :ok
  end

  def ensure_not_member(prefix, user) do
    case Authorization.get_group_by_slug(prefix, @slug) do
      nil -> :ok
      group -> Authorization.remove_member(prefix, user, group)
    end

    :ok
  end
end
