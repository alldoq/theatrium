defmodule Atrium.Accounts.IdpTest do
  use Atrium.TenantCase
  alias Atrium.Accounts.Idp

  describe "create_idp/2" do
    test "creates an OIDC IdP with required fields", %{tenant_prefix: prefix} do
      {:ok, idp} = Idp.create_idp(prefix, %{
        kind: "oidc",
        name: "Entra",
        discovery_url: "https://login.microsoftonline.com/tenantid/v2.0/.well-known/openid-configuration",
        client_id: "abc",
        client_secret: "s3cret"
      })
      assert idp.kind == "oidc"
      assert idp.enabled
      assert idp.client_secret == "s3cret"
    end

    test "rejects SAML without metadata_xml", %{tenant_prefix: prefix} do
      {:error, cs} = Idp.create_idp(prefix, %{kind: "saml", name: "Okta"})
      assert %{metadata_xml: ["can't be blank"]} = errors_on(cs)
    end

    test "only one default allowed", %{tenant_prefix: prefix} do
      {:ok, _} = Idp.create_idp(prefix, %{kind: "oidc", name: "A", discovery_url: "x", client_id: "a", client_secret: "s", is_default: true})
      {:error, _} = Idp.create_idp(prefix, %{kind: "oidc", name: "B", discovery_url: "y", client_id: "b", client_secret: "t", is_default: true})
    end
  end

  describe "list_enabled/1" do
    test "returns only enabled IdPs sorted with default first", %{tenant_prefix: prefix} do
      {:ok, a} = Idp.create_idp(prefix, %{kind: "oidc", name: "A", discovery_url: "x", client_id: "a", client_secret: "s"})
      {:ok, _b} = Idp.create_idp(prefix, %{kind: "oidc", name: "B", discovery_url: "y", client_id: "b", client_secret: "t", enabled: false})
      {:ok, c} = Idp.create_idp(prefix, %{kind: "oidc", name: "C", discovery_url: "z", client_id: "c", client_secret: "u", is_default: true})

      list = Idp.list_enabled(prefix)
      assert [first, second] = list
      assert first.id == c.id
      assert second.id == a.id
    end
  end
end
