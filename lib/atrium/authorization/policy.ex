defmodule Atrium.Authorization.Policy do
  @moduledoc """
  The single source of truth for "can this user do X on target Y?".

  Rule:
  - principals = [{:user, user.id}] ++ [{:group, gid} for gid in user's groups]
  - For target {:subsection, section, sub}: for each principal, if any
    subsection ACL exists for that principal on that subsection (any capability),
    the subsection decides for that principal (child wins for that principal).
    Otherwise fall through to the section ACL.
  - For target {:section, section}: look up section ACL directly.
  """
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Accounts.User
  alias Atrium.Authorization
  alias Atrium.Authorization.{SectionAcl, SubsectionAcl, SectionRegistry}

  @type target :: {:section, String.t() | atom()} | {:subsection, String.t() | atom(), String.t()}
  @type capability :: :view | :edit | :approve

  @valid_caps [:view, :edit, :approve]

  @spec can?(String.t(), User.t(), capability(), target()) :: boolean()
  def can?(prefix, %User{} = user, capability, target) when capability in @valid_caps do
    section_key =
      case target do
        {:section, k} -> to_string(k)
        {:subsection, k, _} -> to_string(k)
      end

    cap = to_string(capability)

    cond do
      is_nil(SectionRegistry.get(section_key)) ->
        false

      match?({:subsection, _, _}, target) ->
        resolve_subsection(prefix, user, cap, target)

      true ->
        principals = principals_for(prefix, user)
        any_section_grant?(prefix, section_key, principals, cap)
    end
  end

  def can?(_prefix, _user, _capability, _target), do: false

  # Internal ---------------------------------------------------------------

  defp resolve_subsection(prefix, user, cap, {:subsection, section_key, sub_slug}) do
    section_key = to_string(section_key)
    principals = principals_for(prefix, user)

    # For each principal, determine effective ACL set on this subsection.
    Enum.any?(principals, fn principal ->
      case subsection_rows_for(prefix, section_key, sub_slug, principal) do
        [] ->
          # Fall through to parent for this principal
          section_grant?(prefix, section_key, principal, cap)

        rows ->
          # Child decides for this principal
          Enum.any?(rows, &(&1.capability == cap))
      end
    end)
  end

  defp principals_for(prefix, %User{id: id} = user) do
    group_ids = Authorization.list_groups_for_user(prefix, user) |> Enum.map(& &1.id)
    [{"user", id}] ++ Enum.map(group_ids, &{"group", &1})
  end

  defp subsection_rows_for(prefix, section_key, sub_slug, {ptype, pid}) do
    Repo.all(
      from(a in SubsectionAcl,
        where:
          a.section_key == ^section_key and
            a.subsection_slug == ^sub_slug and
            a.principal_type == ^ptype and
            a.principal_id == ^pid,
        select: a
      ),
      prefix: prefix
    )
  end

  defp any_section_grant?(prefix, section_key, principals, cap) do
    Enum.any?(principals, &section_grant?(prefix, section_key, &1, cap))
  end

  defp section_grant?(prefix, section_key, {ptype, pid}, cap) do
    Repo.exists?(
      from(a in SectionAcl,
        where:
          a.section_key == ^section_key and
            a.principal_type == ^ptype and
            a.principal_id == ^pid and
            a.capability == ^cap
      ),
      prefix: prefix
    )
  end
end
