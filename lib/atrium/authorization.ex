defmodule Atrium.Authorization do
  @moduledoc """
  Groups, memberships, subsections, and ACL management for a tenant.

  All permission *decisions* live in `Atrium.Authorization.Policy`.
  """
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Authorization.{Group, Membership, Subsection, SectionAcl, SubsectionAcl}
  alias Atrium.Accounts.User

  # Groups -----------------------------------------------------------------

  def create_group(prefix, attrs) do
    %Group{}
    |> Group.create_changeset(attrs)
    |> Repo.insert(prefix: prefix)
  end

  def update_group(prefix, %Group{} = group, attrs) do
    group |> Group.update_changeset(attrs) |> Repo.update(prefix: prefix)
  end

  def delete_group(_prefix, %Group{kind: "system"}), do: {:error, :cannot_delete_system_group}
  def delete_group(prefix, %Group{} = group), do: Repo.delete(group, prefix: prefix)

  def get_group!(prefix, id), do: Repo.get!(Group, id, prefix: prefix)
  def get_group_by_slug(prefix, slug), do: Repo.get_by(Group, [slug: slug], prefix: prefix)

  def list_groups(prefix) do
    Repo.all(from(g in Group, order_by: [asc: g.name]), prefix: prefix)
  end

  # Memberships ------------------------------------------------------------

  def add_member(prefix, %User{id: uid}, %Group{id: gid}) do
    %Membership{}
    |> Membership.changeset(%{user_id: uid, group_id: gid})
    |> Repo.insert(prefix: prefix, on_conflict: :nothing, conflict_target: [:user_id, :group_id])
  end

  def remove_member(prefix, %User{id: uid}, %Group{id: gid}) do
    {_count, _} =
      Repo.delete_all(
        from(m in Membership, where: m.user_id == ^uid and m.group_id == ^gid),
        prefix: prefix
      )

    :ok
  end

  def list_groups_for_user(prefix, %User{id: uid}) do
    Repo.all(
      from(g in Group,
        join: m in Membership, on: m.group_id == g.id,
        where: m.user_id == ^uid,
        order_by: [asc: g.name]
      ),
      prefix: prefix
    )
  end

  def list_members(prefix, %Group{id: gid}) do
    Repo.all(
      from(u in User,
        join: m in Membership, on: m.user_id == u.id,
        where: m.group_id == ^gid,
        order_by: [asc: u.email]
      ),
      prefix: prefix
    )
  end

  # Subsections ------------------------------------------------------------

  def create_subsection(prefix, attrs) do
    %Subsection{}
    |> Subsection.create_changeset(attrs)
    |> Repo.insert(prefix: prefix)
  end

  def delete_subsection(prefix, %Subsection{} = ss) do
    Repo.transaction(fn ->
      Repo.delete_all(
        from(a in SubsectionAcl,
          where: a.section_key == ^ss.section_key and a.subsection_slug == ^ss.slug
        ),
        prefix: prefix
      )

      Repo.delete(ss, prefix: prefix)
    end)
  end

  def list_subsections(prefix, section_key) do
    Repo.all(
      from(s in Subsection, where: s.section_key == ^section_key, order_by: [asc: s.name]),
      prefix: prefix
    )
  end

  # Section ACLs -----------------------------------------------------------

  def grant_section(prefix, section_key, principal, capability, granted_by \\ nil)

  def grant_section(prefix, section_key, {type, id}, capability, granted_by) when type in [:user, :group] do
    %SectionAcl{}
    |> SectionAcl.changeset(%{
      section_key: to_string(section_key),
      principal_type: to_string(type),
      principal_id: id,
      capability: to_string(capability),
      granted_by: granted_by
    })
    |> Repo.insert(prefix: prefix, on_conflict: :nothing,
      conflict_target: [:section_key, :principal_type, :principal_id, :capability])
  end

  def revoke_section(prefix, section_key, {type, id}, capability) when type in [:user, :group] do
    {_count, _} =
      Repo.delete_all(
        from(a in SectionAcl,
          where:
            a.section_key == ^to_string(section_key) and
              a.principal_type == ^to_string(type) and
              a.principal_id == ^id and
              a.capability == ^to_string(capability)
        ),
        prefix: prefix
      )

    :ok
  end

  def list_section_acls(prefix, section_key) do
    Repo.all(
      from(a in SectionAcl, where: a.section_key == ^to_string(section_key)),
      prefix: prefix
    )
  end

  # Subsection ACLs --------------------------------------------------------

  def grant_subsection(prefix, section_key, subsection_slug, principal, capability, granted_by \\ nil)

  def grant_subsection(prefix, section_key, subsection_slug, {type, id}, capability, granted_by)
      when type in [:user, :group] do
    %SubsectionAcl{}
    |> SubsectionAcl.changeset(%{
      section_key: to_string(section_key),
      subsection_slug: subsection_slug,
      principal_type: to_string(type),
      principal_id: id,
      capability: to_string(capability),
      granted_by: granted_by
    })
    |> Repo.insert(prefix: prefix, on_conflict: :nothing,
      conflict_target: [:section_key, :subsection_slug, :principal_type, :principal_id, :capability])
  end

  def revoke_subsection(prefix, section_key, subsection_slug, {type, id}, capability)
      when type in [:user, :group] do
    {_count, _} =
      Repo.delete_all(
        from(a in SubsectionAcl,
          where:
            a.section_key == ^to_string(section_key) and
              a.subsection_slug == ^subsection_slug and
              a.principal_type == ^to_string(type) and
              a.principal_id == ^id and
              a.capability == ^to_string(capability)
        ),
        prefix: prefix
      )

    :ok
  end

  def list_subsection_acls(prefix, section_key, subsection_slug) do
    Repo.all(
      from(a in SubsectionAcl,
        where: a.section_key == ^to_string(section_key) and a.subsection_slug == ^subsection_slug
      ),
      prefix: prefix
    )
  end
end
