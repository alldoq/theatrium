defprotocol Atrium.Audit.Redactable do
  @fallback_to_any true
  @doc "Returns the list of field names to redact before storing in audit changes."
  def redactions(struct)
end

defimpl Atrium.Audit.Redactable, for: Any do
  def redactions(_), do: []
end

defimpl Atrium.Audit.Redactable, for: Atrium.Accounts.User do
  def redactions(_), do: [:password, :hashed_password]
end

defimpl Atrium.Audit.Redactable, for: Atrium.Accounts.IdpConfiguration do
  def redactions(_), do: [:client_secret]
end

defimpl Atrium.Audit.Redactable, for: Atrium.SuperAdmins.SuperAdmin do
  def redactions(_), do: [:password, :hashed_password]
end
