defmodule AtriumWeb.Components.HistoryView do
  use Phoenix.Component

  attr :events, :list, required: true
  attr :title, :string, default: "History"

  def history(assigns) do
    ~H"""
    <div>
      <div class="atrium-card-header">
        <span class="atrium-card-title"><%= @title %></span>
      </div>
      <%= if @events == [] do %>
        <div style="padding:24px 20px;color:var(--text-tertiary);font-size:.875rem">No history yet.</div>
      <% else %>
        <div style="padding:8px 0">
          <%= for e <- @events do %>
            <div style="display:flex;gap:12px;padding:10px 20px;border-bottom:1px solid var(--border)">
              <div style="display:flex;flex-direction:column;align-items:center;flex-shrink:0;padding-top:2px">
                <div style="width:8px;height:8px;border-radius:50%;background:var(--blue-400,#60a5fa);flex-shrink:0"></div>
              </div>
              <div style="flex:1;min-width:0">
                <div style="display:flex;align-items:baseline;justify-content:space-between;gap:8px;flex-wrap:wrap">
                  <span style="font-size:.8125rem;font-weight:600;color:var(--text-primary);font-family:'IBM Plex Mono',monospace"><%= e.action %></span>
                  <span style="font-size:.75rem;color:var(--text-tertiary);white-space:nowrap"><%= Calendar.strftime(e.occurred_at, "%d %b %Y %H:%M") %></span>
                </div>
                <%= if e.changes && e.changes != %{} do %>
                  <div style="margin-top:4px;display:flex;flex-wrap:wrap;gap:4px">
                    <%= for {key, [old, new]} <- e.changes do %>
                      <span style="font-size:.75rem;background:var(--surface-raised,#f8fafc);border:1px solid var(--border);border-radius:4px;padding:1px 6px;color:var(--text-secondary)">
                        <%= key %>:
                        <span style="color:var(--text-tertiary)"><%= inspect(old) %></span>
                        <span style="color:var(--text-tertiary)">→</span>
                        <span style="color:var(--text-primary)"><%= inspect(new) %></span>
                      </span>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
