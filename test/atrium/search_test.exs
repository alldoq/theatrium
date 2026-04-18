defmodule Atrium.SearchTest do
  use Atrium.TenantCase
  alias Atrium.Search
  alias Atrium.Accounts
  alias Atrium.Documents
  alias Atrium.Tools

  defp create_user(prefix, attrs \\ %{}) do
    default = %{
      email: "user_#{System.unique_integer([:positive])}@example.com",
      name: "Search User"
    }
    {:ok, %{user: user, token: raw}} = Accounts.invite_user(prefix, Map.merge(default, attrs))
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    user
  end

  defp create_document(prefix, author, attrs \\ %{}) do
    default = %{title: "Default Doc", section_key: "compliance", body_html: "<p>body</p>"}
    {:ok, doc} = Documents.create_document(prefix, Map.merge(default, attrs), author)
    {:ok, doc} = Documents.approve_document(prefix, submit_to_review(prefix, doc, author), author)
    doc
  end

  defp submit_to_review(prefix, doc, author) do
    {:ok, reviewed} = Documents.submit_for_review(prefix, doc, author)
    reviewed
  end

  defp create_tool(prefix, author, attrs \\ %{}) do
    default = %{
      label: "Default Tool",
      description: "A tool description",
      kind: "link",
      url: "https://example.com"
    }
    {:ok, tool} = Tools.create_tool_link(prefix, Map.merge(default, attrs), author)
    tool
  end

  describe "search_documents/3" do
    test "returns approved documents matching title", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      _doc = create_document(prefix, author, %{title: "Parental Leave Policy", section_key: "hr"})

      results = Search.search_documents(prefix, "parental", ["hr"])
      assert length(results) == 1
      assert hd(results).title == "Parental Leave Policy"
    end

    test "returns approved documents matching body_html", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      _doc = create_document(prefix, author, %{
        title: "HR Policy",
        section_key: "hr",
        body_html: "<p>remote working guidelines</p>"
      })

      results = Search.search_documents(prefix, "remote working", ["hr"])
      assert length(results) == 1
    end

    test "returns [] when query is shorter than 2 chars", %{tenant_prefix: prefix} do
      assert Search.search_documents(prefix, "a", ["hr"]) == []
      assert Search.search_documents(prefix, "", ["hr"]) == []
    end

    test "does not return documents from sections not in section_keys", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      _doc = create_document(prefix, author, %{title: "Compliance Doc", section_key: "compliance"})

      results = Search.search_documents(prefix, "Compliance", ["hr"])
      assert results == []
    end

    test "returns [] when section_keys is empty", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      _doc = create_document(prefix, author, %{title: "Anything", section_key: "hr"})

      assert Search.search_documents(prefix, "anything", []) == []
    end

    test "is case-insensitive", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      _doc = create_document(prefix, author, %{title: "Annual Report", section_key: "compliance"})

      assert length(Search.search_documents(prefix, "ANNUAL", ["compliance"])) == 1
      assert length(Search.search_documents(prefix, "annual", ["compliance"])) == 1
    end

    test "does not return draft documents", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      {:ok, _draft} = Documents.create_document(
        prefix,
        %{title: "Draft Policy", section_key: "hr", body_html: "draft"},
        author
      )

      results = Search.search_documents(prefix, "Draft Policy", ["hr"])
      assert results == []
    end
  end

  describe "search_users/2" do
    test "matches active users by name", %{tenant_prefix: prefix} do
      _alice = create_user(prefix, %{email: "alice@example.com", name: "Alice Wonderland"})

      results = Search.search_users(prefix, "wonderland")
      assert Enum.any?(results, &(&1.name == "Alice Wonderland"))
    end

    test "matches active users by email", %{tenant_prefix: prefix} do
      _bob = create_user(prefix, %{email: "bob.unique@example.com", name: "Bob Smith"})

      results = Search.search_users(prefix, "bob.unique")
      assert Enum.any?(results, &(&1.email == "bob.unique@example.com"))
    end

    test "matches by role and department", %{tenant_prefix: prefix} do
      user = create_user(prefix, %{email: "eng@example.com", name: "Eng Person"})
      {:ok, _} = Accounts.update_profile(prefix, user, %{
        name: "Eng Person",
        role: "Senior Engineer",
        department: "Platform"
      })

      assert Enum.any?(Search.search_users(prefix, "Senior Engineer"), &(&1.email == "eng@example.com"))
      assert Enum.any?(Search.search_users(prefix, "Platform"), &(&1.email == "eng@example.com"))
    end

    test "returns [] when query is shorter than 2 chars", %{tenant_prefix: prefix} do
      assert Search.search_users(prefix, "x") == []
      assert Search.search_users(prefix, "") == []
    end

    test "does not return suspended users", %{tenant_prefix: prefix} do
      user = create_user(prefix, %{email: "suspended@example.com", name: "Suspended Person"})
      {:ok, _} = Accounts.suspend_user(prefix, user)

      results = Search.search_users(prefix, "Suspended Person")
      assert results == []
    end
  end

  describe "search_tools/2" do
    test "matches tools by label", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      _tool = create_tool(prefix, author, %{label: "Jira Tickets", url: "https://jira.example.com"})

      results = Search.search_tools(prefix, "jira")
      assert Enum.any?(results, &(&1.label == "Jira Tickets"))
    end

    test "matches tools by description", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      _tool = create_tool(prefix, author, %{
        label: "Some Tool",
        description: "Used for performance reviews",
        url: "https://perf.example.com"
      })

      results = Search.search_tools(prefix, "performance reviews")
      assert Enum.any?(results, &(&1.label == "Some Tool"))
    end

    test "returns [] when query is shorter than 2 chars", %{tenant_prefix: prefix} do
      assert Search.search_tools(prefix, "x") == []
    end
  end
end
