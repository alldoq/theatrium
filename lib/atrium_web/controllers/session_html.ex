defmodule AtriumWeb.SessionHTML do
  use AtriumWeb, :html
  embed_templates "session_html/*"

  def idp_start_path(%{kind: "oidc", id: id}), do: ~p"/auth/oidc/#{id}/start"
  def idp_start_path(%{kind: "saml", id: id}), do: ~p"/auth/saml/#{id}/start"
end
