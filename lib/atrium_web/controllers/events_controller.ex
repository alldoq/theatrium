defmodule AtriumWeb.EventsController do
  use AtriumWeb, :controller
  alias Atrium.Events

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "events"}]
       when action in [:index, :show]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: {:section, "events"}]
       when action in [:new, :create, :edit, :update, :delete]

  def index(conn, params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    today = Date.utc_today()

    view = parse_view(params)

    {year, month} = parse_year_month(params)
    week_start = parse_week_start(params, today)
    day = parse_day(params, today)

    events =
      case view do
        "month" -> Events.list_events_for_month(prefix, year, month)
        "week" -> Events.list_events_for_week(prefix, week_start)
        "day" -> Events.list_events_for_day(prefix, day)
      end

    upcoming = Events.list_upcoming_events(prefix, DateTime.utc_now(), 10)
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "events"})

    render(conn, :index,
      events: events,
      view: view,
      year: year,
      month: month,
      week_start: week_start,
      day: day,
      today: today,
      upcoming: upcoming,
      can_edit: can_edit
    )
  end

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    event = Events.get_event!(prefix, id)
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "events"})
    render(conn, :show, event: event, can_edit: can_edit)
  end

  def new(conn, _params) do
    render(conn, :new, changeset: changeset_for_new())
  end

  def create(conn, %{"event" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Events.create_event(prefix, params, user) do
      {:ok, event} ->
        conn
        |> put_flash(:info, "Event created.")
        |> redirect(to: ~p"/events/#{event.id}")

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Could not save event.")
        |> render(:new, changeset: changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    event = Events.get_event!(prefix, id)
    render(conn, :edit, event: event, changeset: Atrium.Events.Event.changeset(event, %{}))
  end

  def update(conn, %{"id" => id, "event" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    event = Events.get_event!(prefix, id)

    case Events.update_event(prefix, event, params, user) do
      {:ok, updated} ->
        conn
        |> put_flash(:info, "Event updated.")
        |> redirect(to: ~p"/events/#{updated.id}")

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Could not update event.")
        |> render(:edit, event: event, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    event = Events.get_event!(prefix, id)

    case Events.delete_event(prefix, event, user) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Event deleted.")
        |> redirect(to: ~p"/events")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not delete event.")
        |> redirect(to: ~p"/events/#{id}")
    end
  end

  defp parse_view(%{"view" => v}) when v in ~w(month week day), do: v
  defp parse_view(_), do: "month"

  defp parse_year_month(%{"year" => y, "month" => m}) do
    year = String.to_integer(y)
    month = String.to_integer(m)
    now = Date.utc_today()
    year = if year < 2000 or year > 2100, do: now.year, else: year
    month = if month < 1 or month > 12, do: now.month, else: month
    {year, month}
  end

  defp parse_year_month(_) do
    today = Date.utc_today()
    {today.year, today.month}
  end

  defp parse_week_start(%{"week" => w}, _today) do
    case Date.from_iso8601(w) do
      {:ok, d} -> Date.beginning_of_week(d)
      _ -> Date.beginning_of_week(Date.utc_today())
    end
  end
  defp parse_week_start(_, today), do: Date.beginning_of_week(today)

  defp parse_day(%{"day" => d}, _today) do
    case Date.from_iso8601(d) do
      {:ok, date} -> date
      _ -> Date.utc_today()
    end
  end
  defp parse_day(_, today), do: today

  defp changeset_for_new do
    Atrium.Events.Event.changeset(%Atrium.Events.Event{}, %{})
  end
end
