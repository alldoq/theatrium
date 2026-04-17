defmodule Atrium.Tenants.ThemeTest do
  use ExUnit.Case, async: true
  alias Atrium.Tenants.Theme

  test "default/0 returns all required keys with string values" do
    theme = Theme.default()
    assert is_binary(theme.primary)
    assert is_binary(theme.secondary)
    assert is_binary(theme.accent)
    assert is_binary(theme.font)
    assert theme.logo_url == nil
  end

  test "from_map/1 casts string-keyed map into struct and fills missing with defaults" do
    input = %{"primary" => "#112233", "logo_url" => "https://example.com/logo.svg"}
    theme = Theme.from_map(input)
    assert theme.primary == "#112233"
    assert theme.logo_url == "https://example.com/logo.svg"
    assert theme.secondary == Theme.default().secondary
  end
end
