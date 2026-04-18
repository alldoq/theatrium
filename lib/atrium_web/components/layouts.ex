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

  @doc """
  Renders the app layout

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layout.app>
      
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-screen">
      <nav class="w-64 border-r bg-slate-50 p-4" style="background-color: var(--color-primary); color: white;">
        <%= if assigns[:tenant] do %>
          <div class="mb-6">
            <%= if assigns[:tenant].theme["logo_url"] do %>
              <img src={@tenant.theme["logo_url"]} alt={@tenant.name} class="h-8" />
            <% else %>
              <h1 class="text-lg font-semibold"><%= @tenant.name %></h1>
            <% end %>
          </div>
        <% end %>

        <%= if assigns[:nav] do %>
          <ul class="space-y-1">
            <%= for entry <- @nav do %>
              <li>
                <.link href={"/sections/#{entry.key}"} class="block rounded px-2 py-1 hover:bg-white/10">
                  <%= entry.name %>
                </.link>
                <%= if entry.children != [] do %>
                  <ul class="ml-4 mt-1 space-y-1">
                    <%= for c <- entry.children do %>
                      <li>
                        <.link href={"/sections/#{entry.key}/#{c.slug}"} class="block rounded px-2 py-1 text-sm hover:bg-white/10">
                          <%= c.name %>
                        </.link>
                      </li>
                    <% end %>
                  </ul>
                <% end %>
              </li>
            <% end %>
          </ul>
        <% end %>
      </nav>

      <main class="flex-1 p-8">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  def theme_style(%{tenant: %{theme: theme}}) when is_map(theme) do
    [
      {"--color-primary", Map.get(theme, "primary", "#0F172A")},
      {"--color-secondary", Map.get(theme, "secondary", "#64748B")},
      {"--color-accent", Map.get(theme, "accent", "#2563EB")},
      {"--font-sans", Map.get(theme, "font", "Inter, system-ui, sans-serif")}
    ]
    |> Enum.map_join("; ", fn {k, v} -> "#{k}: #{v}" end)
  end

  def theme_style(_), do: ""

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
