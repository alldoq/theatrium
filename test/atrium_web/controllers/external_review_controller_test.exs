defmodule AtriumWeb.ExternalReviewControllerTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.{Tenants, Accounts}
  alias Atrium.Tenants.Provisioner
  alias Atrium.Forms

  setup do
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: "ext_review_test", name: "Ext Review Test"})
    {:ok, tenant} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop("ext_review_test") end)

    prefix = Triplex.to_prefix("ext_review_test")
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{email: "submitter@example.com", name: "Submitter"})
    {:ok, user} = Accounts.activate_user_with_password(prefix, user, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })

    {:ok, form} = Forms.create_form(prefix, %{
      title: "Ext Form",
      section_key: "hr",
      notification_recipients: [%{"type" => "email", "email" => "reviewer@external.com"}]
    }, user)
    {:ok, form} = Forms.publish_form(prefix, form, [], user)
    {:ok, sub} = Forms.create_submission(prefix, form, %{}, user)
    [review] = Forms.list_reviews(prefix, sub.id)

    token = Phoenix.Token.sign(AtriumWeb.Endpoint, "form_review", %{
      "submission_id" => sub.id,
      "reviewer_email" => "reviewer@external.com",
      "prefix" => prefix
    })

    conn = build_conn() |> Map.put(:host, "ext_review_test.atrium.example")

    {:ok, conn: conn, prefix: prefix, review: review, token: token, sub: sub}
  end

  describe "GET /forms/review/:token" do
    test "renders review page with valid token", %{conn: conn, token: token} do
      conn = get(conn, "/forms/review/#{token}")
      assert html_response(conn, 200) =~ "review"
    end

    test "returns 400 for invalid token", %{conn: conn} do
      conn = get(conn, "/forms/review/badtoken")
      assert conn.status == 400
    end

    test "returns 400 for expired token", %{conn: conn, sub: sub, prefix: prefix} do
      expired_token = Phoenix.Token.sign(AtriumWeb.Endpoint, "form_review", %{
        "submission_id" => sub.id,
        "reviewer_email" => "reviewer@external.com",
        "prefix" => prefix
      }, signed_at: System.system_time(:second) - 31 * 24 * 3600)
      conn = get(conn, "/forms/review/#{expired_token}")
      assert conn.status == 400
    end
  end

  describe "POST /forms/review/:token/complete" do
    test "marks review complete and redirects", %{conn: conn, token: token, prefix: prefix, review: review} do
      conn = post(conn, "/forms/review/#{token}/complete")
      assert redirected_to(conn) =~ "/forms/review/#{token}"
      updated = Enum.find(Forms.list_reviews(prefix, review.submission_id), &(&1.id == review.id))
      assert updated.status == "completed"
    end

    test "already-completed review redirects with flash", %{conn: conn, token: token, prefix: prefix, review: review} do
      {:ok, _} = Forms.complete_review(prefix, review, nil)
      conn = post(conn, "/forms/review/#{token}/complete")
      assert redirected_to(conn) =~ "/forms/review/#{token}"
    end
  end
end
