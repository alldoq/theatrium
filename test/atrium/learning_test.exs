defmodule Atrium.LearningTest do
  use Atrium.TenantCase, async: false

  alias Atrium.Learning
  alias Atrium.Learning.{Course, CourseMaterial, CourseCompletion}
  alias Atrium.Accounts

  defp build_user(prefix) do
    {:ok, %{user: user}} =
      Accounts.invite_user(prefix, %{
        email: "learning_actor_#{System.unique_integer([:positive])}@example.com",
        name: "Learning Actor"
      })
    user
  end

  defp build_course(prefix, user, attrs \\ %{}) do
    base = %{title: "Intro to Safety", description: "Safety course", category: "Compliance"}
    Learning.create_course(prefix, Map.merge(base, attrs), user)
  end

  describe "create_course/3" do
    test "creates a course with status draft", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      assert {:ok, %Course{status: "draft", title: "Intro to Safety"}} =
               build_course(prefix, user)
    end

    test "returns error for missing title", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      assert {:error, cs} = Learning.create_course(prefix, %{category: "HR"}, user)
      assert errors_on(cs)[:title]
    end
  end

  describe "publish_course/2" do
    test "sets status to published", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      assert {:ok, %Course{status: "published"}} = Learning.publish_course(prefix, course)
    end
  end

  describe "archive_course/2" do
    test "sets status to archived from published", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      {:ok, course} = Learning.publish_course(prefix, course)
      assert {:ok, %Course{status: "archived"}} = Learning.archive_course(prefix, course)
    end

    test "returns error when archiving a draft", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      assert {:error, _} = Learning.archive_course(prefix, course)
    end
  end

  describe "list_courses/2" do
    test "returns only published courses by default", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, draft} = build_course(prefix, user, %{title: "Draft Course"})
      {:ok, pub} = build_course(prefix, user, %{title: "Published Course"})
      {:ok, _} = Learning.publish_course(prefix, pub)

      results = Learning.list_courses(prefix)
      ids = Enum.map(results, & &1.id)
      assert pub.id in ids
      refute draft.id in ids
    end

    test "returns all courses when status: :all", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, draft} = build_course(prefix, user, %{title: "Draft"})
      {:ok, pub} = build_course(prefix, user, %{title: "Published"})
      {:ok, _} = Learning.publish_course(prefix, pub)

      results = Learning.list_courses(prefix, status: :all)
      ids = Enum.map(results, & &1.id)
      assert draft.id in ids
      assert pub.id in ids
    end
  end

  describe "add_material/3 and list_materials/2" do
    test "adds a URL material", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      assert {:ok, %CourseMaterial{type: "url", title: "OSHA Guide"}} =
               Learning.add_material(prefix, course.id, %{
                 type: "url",
                 title: "OSHA Guide",
                 url: "https://osha.gov/guide",
                 position: 0
               })
    end

    test "returns error for URL material without https", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      assert {:error, cs} =
               Learning.add_material(prefix, course.id, %{
                 type: "url",
                 title: "Bad URL",
                 url: "not-a-url",
                 position: 0
               })
      assert errors_on(cs)[:url]
    end

    test "lists materials ordered by position", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      Learning.add_material(prefix, course.id, %{type: "url", title: "Second", url: "https://b.com", position: 10})
      Learning.add_material(prefix, course.id, %{type: "url", title: "First", url: "https://a.com", position: 0})
      [first, second] = Learning.list_materials(prefix, course.id)
      assert first.title == "First"
      assert second.title == "Second"
    end
  end

  describe "complete_course/3 and uncomplete_course/3" do
    test "marks a course as complete", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      assert {:ok, %CourseCompletion{}} = Learning.complete_course(prefix, course.id, user.id)
      assert Learning.completed?(prefix, course.id, user.id)
    end

    test "complete is idempotent", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      {:ok, _} = Learning.complete_course(prefix, course.id, user.id)
      assert {:ok, _} = Learning.complete_course(prefix, course.id, user.id)
    end

    test "uncomplete removes completion", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      {:ok, _} = Learning.complete_course(prefix, course.id, user.id)
      :ok = Learning.uncomplete_course(prefix, course.id, user.id)
      refute Learning.completed?(prefix, course.id, user.id)
    end

    test "completion_count returns number of completions", %{tenant_prefix: prefix} do
      user1 = build_user(prefix)
      user2 = build_user(prefix)
      {:ok, course} = build_course(prefix, user1)
      Learning.complete_course(prefix, course.id, user1.id)
      Learning.complete_course(prefix, course.id, user2.id)
      assert Learning.completion_count(prefix, course.id) == 2
    end
  end
end
