defmodule Atrium.ScormTest do
  use Atrium.TenantCase, async: false

  alias Atrium.{Accounts, Learning, Scorm}

  @fixture_zip Path.expand("../../fixtures/sexual_harassment_scorm.zip", __DIR__)

  setup do
    unless File.exists?(@fixture_zip) do
      src = "/Users/marcinwalczak/Downloads/Sexual Harrassment Course - SCORM.zip"
      if File.exists?(src) do
        File.mkdir_p!(Path.dirname(@fixture_zip))
        File.cp!(src, @fixture_zip)
      end
    end

    :ok
  end

  defp user(prefix) do
    {:ok, %{user: u}} =
      Accounts.invite_user(prefix, %{
        email: "scorm_actor_#{System.unique_integer([:positive])}@example.com",
        name: "SCORM Actor"
      })
    u
  end

  defp course(prefix, u) do
    {:ok, c} = Learning.create_course(prefix, %{title: "Compliance", category: "HR"}, u)
    c
  end

  defp upload(path) do
    %Plug.Upload{
      path: path,
      filename: "course.zip",
      content_type: "application/zip"
    }
  end

  describe "upload_package/4 with real Articulate Rise package" do
    @tag :scorm_fixture
    test "extracts, parses manifest, persists package", %{tenant_prefix: prefix} do
      unless File.exists?(@fixture_zip) do
        IO.puts("skipping — fixture missing: #{@fixture_zip}")
        :ok
      else
        u = user(prefix)
        c = course(prefix, u)

        assert {:ok, pkg} = Scorm.upload_package(prefix, c.id, upload(@fixture_zip), u)
        assert pkg.title =~ "Sexual Harassment"
        assert pkg.version == "1.2"
        assert pkg.launch_url == "scormdriver/indexAPI.html"
        assert pkg.byte_size > 0
        assert pkg.course_id == c.id

        # extracted file present
        dir = Scorm.package_dir(prefix, pkg.id)
        assert File.regular?(Path.join(dir, "imsmanifest.xml"))
        assert File.regular?(Path.join(dir, "scormdriver/indexAPI.html"))

        # attempt lifecycle
        assert {:ok, attempt} = Scorm.get_or_create_attempt(prefix, pkg, u.id)
        assert attempt.lesson_status == "not attempted"

        # simulate SCORM JS commits
        {:ok, a2} =
          Scorm.commit_attempt(prefix, attempt, %{
            "cmi.core.lesson_status" => "incomplete",
            "cmi.core.score.raw" => "42",
            "cmi.suspend_data" => "chapter:2"
          })

        assert a2.lesson_status == "incomplete"
        assert a2.score_raw == 42.0
        assert a2.suspend_data == "chapter:2"
        refute Scorm.completed?(a2)

        {:ok, a3} = Scorm.commit_attempt(prefix, a2, %{"cmi.core.lesson_status" => "completed"})
        assert Scorm.completed?(a3)
        assert a3.completed_at != nil

        # cleanup
        assert {:ok, _} = Scorm.delete_package(prefix, pkg, u)
        refute File.exists?(dir)
      end
    end
  end
end
