defmodule Atrium.ProjectsTest do
  use Atrium.TenantCase, async: false

  alias Atrium.{Projects, Accounts}

  defp build_user(prefix) do
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{
      email: "proj_#{System.unique_integer([:positive])}@example.com",
      name: "Owner"
    })
    {:ok, user} = Accounts.activate_user_with_password(prefix, user, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    user
  end

  test "create_project/3 creates a project", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Alpha"}, user)
    assert project.title == "Alpha"
    assert project.owner_id == user.id
    assert project.status == "active"
  end

  test "list_projects/1 returns all projects", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, _} = Projects.create_project(prefix, %{"title" => "P1"}, user)
    {:ok, _} = Projects.create_project(prefix, %{"title" => "P2"}, user)
    projects = Projects.list_projects(prefix)
    titles = Enum.map(projects, & &1.title)
    assert "P1" in titles
    assert "P2" in titles
  end

  test "update_project/4 updates fields", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Old"}, user)
    {:ok, updated} = Projects.update_project(prefix, project, %{"title" => "New", "status" => "on_hold"}, user)
    assert updated.title == "New"
    assert updated.status == "on_hold"
  end

  test "add_member/4 and member?/3", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    other = build_user(prefix)
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Team"}, user)
    {:ok, _} = Projects.add_member(prefix, project.id, other.id)
    assert Projects.member?(prefix, project.id, other.id)
  end

  test "remove_member/3 removes membership", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Team"}, user)
    {:ok, _} = Projects.add_member(prefix, project.id, user.id)
    assert :ok = Projects.remove_member(prefix, project.id, user.id)
    refute Projects.member?(prefix, project.id, user.id)
  end

  test "add_update/3 and list_updates/2", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Updates"}, user)
    {:ok, _} = Projects.add_update(prefix, project.id, %{"author_id" => user.id, "body" => "First update"})
    {:ok, _} = Projects.add_update(prefix, project.id, %{"author_id" => user.id, "body" => "Second update"})
    updates = Projects.list_updates(prefix, project.id)
    assert length(updates) == 2
    assert hd(updates).body == "First update"
  end

  test "delete_update/2 removes update", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Del"}, user)
    {:ok, update} = Projects.add_update(prefix, project.id, %{"author_id" => user.id, "body" => "Bye"})
    assert :ok = Projects.delete_update(prefix, update.id)
    assert Projects.list_updates(prefix, project.id) == []
  end

  test "delete_update/2 returns error for missing update", %{tenant_prefix: prefix} do
    assert {:error, :not_found} = Projects.delete_update(prefix, Ecto.UUID.generate())
  end

  test "count_members/2 counts correctly", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Count"}, user)
    {:ok, _} = Projects.add_member(prefix, project.id, user.id)
    assert Projects.count_members(prefix, project.id) == 1
  end
end
