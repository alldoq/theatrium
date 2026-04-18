defmodule Atrium.Authorization do
  @moduledoc """
  Groups, memberships, subsections, and ACL management for a tenant.

  All permission *decisions* live in `Atrium.Authorization.Policy`.
  """
  import Ecto.Query
  alias Atrium.Audit
  alias Atrium.Repo
  alias Atrium.Authorization.{Group, Membership, Subsection, SectionAcl, SubsectionAcl}
  alias Atrium.Accounts.User

  # Groups -----------------------------------------------------------------

  def create_group(prefix, attrs) do
    with {:ok, group} <- %Group{} |> Group.create_changeset(attrs) |> Repo.insert(prefix: prefix) do
      {:ok, _} = Audit.log(prefix, "group.created", %{actor: :system, resource: {"Group", group.id}})
      {:ok, group}
    end
  end

  def update_group(prefix, %Group{} = group, attrs) do
    with {:ok, updated} <- group |> Group.update_changeset(attrs) |> Repo.update(prefix: prefix) do
      {:ok, _} = Audit.log(prefix, "group.updated", %{actor: :system, resource: {"Group", updated.id}})
      {:ok, updated}
    end
  end

  def delete_group(_prefix, %Group{kind: "system"}), do: {:error, :cannot_delete_system_group}
  def delete_group(prefix, %Group{} = group) do
    with {:ok, deleted} <- Repo.delete(group, prefix: prefix) do
      {:ok, _} = Audit.log(prefix, "group.deleted", %{actor: :system, resource: {"Group", deleted.id}})
      {:ok, deleted}
    end
  end

  def get_group!(prefix, id), do: Repo.get!(Group, id, prefix: prefix)
  def get_group_by_slug(prefix, slug), do: Repo.get_by(Group, [slug: slug], prefix: prefix)

  def list_groups(prefix) do
    Repo.all(from(g in Group, order_by: [asc: g.name]), prefix: prefix)
  end

  # Memberships ------------------------------------------------------------

  def add_member(prefix, %User{id: uid}, %Group{id: gid}) do
    with {:ok, m} <-
           %Membership{}
           |> Membership.changeset(%{user_id: uid, group_id: gid})
           |> Repo.insert(prefix: prefix, on_conflict: :nothing, conflict_target: [:user_id, :group_id]) do
      if m.id do
        {:ok, _} = Audit.log(prefix, "membership.added", %{actor: :system, resource: {"Membership", m.id}})
      end
      {:ok, m}
    end
  end

  def remove_member(prefix, %User{id: uid}, %Group{id: gid}) do
    {_count, _} =
      Repo.delete_all(
        from(m in Membership, where: m.user_id == ^uid and m.group_id == ^gid),
        prefix: prefix
      )

    {:ok, _} = Audit.log(prefix, "membership.removed", %{actor: :system, context: %{"user_id" => uid, "group_id" => gid}})
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
    with {:ok, ss} <- %Subsection{} |> Subsection.create_changeset(attrs) |> Repo.insert(prefix: prefix) do
      {:ok, _} = Audit.log(prefix, "subsection.created", %{actor: :system, resource: {"Subsection", ss.id}})
      {:ok, ss}
    end
  end

  def delete_subsection(prefix, %Subsection{} = ss) do
    result =
      Repo.transaction(fn ->
        Repo.delete_all(
          from(a in SubsectionAcl,
            where: a.section_key == ^ss.section_key and a.subsection_slug == ^ss.slug
          ),
          prefix: prefix
        )

        Repo.delete(ss, prefix: prefix)
      end)

    case result do
      {:ok, {:ok, deleted}} ->
        {:ok, _} = Audit.log(prefix, "subsection.deleted", %{actor: :system, resource: {"Subsection", deleted.id}})
        result

      _ ->
        result
    end
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
    with {:ok, acl} <-
           %SectionAcl{}
           |> SectionAcl.changeset(%{
             section_key: to_string(section_key),
             principal_type: to_string(type),
             principal_id: id,
             capability: to_string(capability),
             granted_by: granted_by
           })
           |> Repo.insert(prefix: prefix, on_conflict: :nothing,
             conflict_target: [:section_key, :principal_type, :principal_id, :capability]) do
      if acl.id do
        actor = if granted_by, do: {:user, granted_by}, else: :system
        {:ok, _} = Audit.log(prefix, "section_acl.granted", %{actor: actor, resource: {"SectionAcl", acl.id}})
      end
      {:ok, acl}
    end
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

    {:ok, _} = Audit.log(prefix, "section_acl.revoked", %{actor: :system, context: %{"section_key" => to_string(section_key), "capability" => to_string(capability)}})
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
    with {:ok, acl} <-
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
             conflict_target: [:section_key, :subsection_slug, :principal_type, :principal_id, :capability]) do
      if acl.id do
        actor = if granted_by, do: {:user, granted_by}, else: :system
        {:ok, _} = Audit.log(prefix, "subsection_acl.granted", %{actor: actor, resource: {"SubsectionAcl", acl.id}})
      end
      {:ok, acl}
    end
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

    {:ok, _} = Audit.log(prefix, "subsection_acl.revoked", %{actor: :system, context: %{"section_key" => to_string(section_key), "subsection_slug" => subsection_slug, "capability" => to_string(capability)}})
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
