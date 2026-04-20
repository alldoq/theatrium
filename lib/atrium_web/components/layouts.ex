defmodule AtriumWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is rendered as component
  in regular views and live views.
  """
  use AtriumWeb, :html

  embed_templates "layouts/*"

  def theme_style(%{tenant: %{theme: theme}}) when is_map(theme) do
    accent   = normalize_hex(Map.get(theme, "accent", "#2563eb"))
    nav_bg   = normalize_hex(Map.get(theme, "secondary", "#1e293b"))
    font     = Map.get(theme, "font", nil)

    vars = [
      # Accent palette — --blue-500 is the base; derive neighbours
      {"--blue-500", accent},
      {"--blue-600", darken(accent, 0.12)},
      {"--blue-400", lighten(accent, 0.15)},
      {"--blue-100", lighten(accent, 0.75)},
      {"--blue-50",  lighten(accent, 0.88)},
      # Nav/sidebar background
      {"--slate-800", nav_bg},
    ]

    vars = if font, do: [{"--brand-font", font} | vars], else: vars

    Enum.map_join(vars, "; ", fn {k, v} -> "#{k}: #{v}" end)
  end

  def theme_style(_), do: ""

  defp normalize_hex(nil), do: nil
  defp normalize_hex("#" <> _ = hex), do: hex
  defp normalize_hex(hex) when is_binary(hex), do: "#" <> hex

  # Lighten a hex color by blending toward white by `amount` (0..1).
  defp lighten(hex, amount) do
    {r, g, b} = parse_hex(hex)
    r2 = round(r + (255 - r) * amount)
    g2 = round(g + (255 - g) * amount)
    b2 = round(b + (255 - b) * amount)
    format_hex(r2, g2, b2)
  end

  # Darken a hex color by blending toward black by `amount` (0..1).
  defp darken(hex, amount) do
    {r, g, b} = parse_hex(hex)
    r2 = round(r * (1 - amount))
    g2 = round(g * (1 - amount))
    b2 = round(b * (1 - amount))
    format_hex(r2, g2, b2)
  end

  defp parse_hex("#" <> hex) do
    hex = String.downcase(hex)
    {r, _} = Integer.parse(String.slice(hex, 0, 2), 16)
    {g, _} = Integer.parse(String.slice(hex, 2, 2), 16)
    {b, _} = Integer.parse(String.slice(hex, 4, 2), 16)
    {r, g, b}
  end
  defp parse_hex(hex), do: parse_hex("#" <> hex)

  defp format_hex(r, g, b) do
    "##{Integer.to_string(r, 16) |> String.pad_leading(2, "0")}#{Integer.to_string(g, 16) |> String.pad_leading(2, "0")}#{Integer.to_string(b, 16) |> String.pad_leading(2, "0")}"
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "system"})}
        class="flex p-2 cursor-pointer w-1/3"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "light"})}
        class="flex p-2 cursor-pointer w-1/3"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "dark"})}
        class="flex p-2 cursor-pointer w-1/3"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
