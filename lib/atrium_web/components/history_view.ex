defmodule AtriumWeb.Components.HistoryView do
  use Phoenix.Component

  attr :events, :list, required: true
  attr :title, :string, default: "History"

  def history(assigns) do
    ~H"""
    <section class="border rounded">
      <h3 class="p-3 border-b font-semibold"><%= @title %></h3>
      <ul class="divide-y">
        <%= for e <- @events do %>
          <li class="p-3 text-sm">
            <div class="flex justify-between">
              <span class="font-mono"><%= e.action %></span>
              <span class="text-gray-500"><%= Calendar.strftime(e.occurred_at, "%Y-%m-%d %H:%M") %></span>
            </div>
            <div class="text-gray-700 mt-1">
              <%= render_changes(e.changes) %>
            </div>
          </li>
        <% end %>
      </ul>
    </section>
    """
  end

  defp render_changes(changes) when changes == %{}, do: ""
  defp render_changes(changes) do
    changes
    |> Enum.map(fn {key, [old, new]} -> "#{key}: #{inspect(old)} → #{inspect(new)}" end)
    |> Enum.join("; ")
  end
end
