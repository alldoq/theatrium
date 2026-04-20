defmodule AtriumWeb.NewsController do
  use AtriumWeb, :controller
  alias Atrium.Documents

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "news"}]
       when action in [:index, :show]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    articles = Documents.list_documents(prefix, "news", status: "approved")
    render(conn, :index, articles: articles)
  end

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    article = Documents.get_document!(prefix, id)
    render(conn, :show, article: article)
  end
end
