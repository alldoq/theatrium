defmodule AtriumWeb.DocumentController do
  use AtriumWeb, :controller
  alias Atrium.Documents
  alias Atrium.Documents.Document

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: &__MODULE__.section_target/1]
       when action in [:index, :show]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: &__MODULE__.section_target/1]
       when action in [:new, :create, :edit, :update, :submit]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :approve, target: &__MODULE__.section_target/1]
       when action in [:reject, :approve, :archive]

  def section_target(conn), do: {:section, conn.path_params["section_key"]}

  def index(conn, %{"section_key" => section_key} = params) do
    prefix = conn.assigns.tenant_prefix
    opts = []
    opts = if s = params["subsection_slug"], do: Keyword.put(opts, :subsection_slug, s), else: opts
    opts = if st = params["status"], do: Keyword.put(opts, :status, st), else: opts
    documents = Documents.list_documents(prefix, section_key, opts)
    render(conn, :index, documents: documents, section_key: section_key)
  end

  def new(conn, %{"section_key" => section_key}) do
    changeset = Document.changeset(%Document{}, %{})
    render(conn, :new, changeset: changeset, section_key: section_key)
  end

  def create(conn, %{"section_key" => section_key, "document" => doc_params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    attrs = Map.put(doc_params, "section_key", section_key)

    case Documents.create_document(prefix, attrs, user) do
      {:ok, doc} ->
        conn
        |> put_flash(:info, "Document created.")
        |> redirect(to: ~p"/sections/#{section_key}/documents/#{doc.id}")

      {:error, changeset} ->
        render(conn, :new, changeset: changeset, section_key: section_key, status: 422)
    end
  end

  def show(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    doc = Documents.get_document!(prefix, id)
    versions = Documents.list_versions(prefix, doc.id)
    render(conn, :show, document: doc, versions: versions, section_key: section_key)
  end

  def edit(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    doc = Documents.get_document!(prefix, id)
    changeset = Document.update_changeset(doc, %{})
    render(conn, :edit, document: doc, changeset: changeset, section_key: section_key)
  end

  def update(conn, %{"section_key" => section_key, "id" => id, "document" => doc_params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    doc = Documents.get_document!(prefix, id)

    case Documents.update_document(prefix, doc, doc_params, user) do
      {:ok, updated} ->
        conn
        |> put_flash(:info, "Document updated.")
        |> redirect(to: ~p"/sections/#{section_key}/documents/#{updated.id}")

      {:error, :not_draft} ->
        conn
        |> put_flash(:error, "Only draft documents can be edited.")
        |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}")

      {:error, changeset} ->
        render(conn, :edit, document: doc, changeset: changeset, section_key: section_key, status: 422)
    end
  end

  def submit(conn, %{"section_key" => section_key, "id" => id}) do
    run_transition(conn, section_key, id, &Documents.submit_for_review/3, "Document submitted for review.")
  end

  def reject(conn, %{"section_key" => section_key, "id" => id}) do
    run_transition(conn, section_key, id, &Documents.reject_document/3, "Document returned to draft.")
  end

  def approve(conn, %{"section_key" => section_key, "id" => id}) do
    run_transition(conn, section_key, id, &Documents.approve_document/3, "Document approved.")
  end

  def archive(conn, %{"section_key" => section_key, "id" => id}) do
    run_transition(conn, section_key, id, &Documents.archive_document/3, "Document archived.")
  end

  defp run_transition(conn, section_key, id, transition_fn, success_msg) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    doc = Documents.get_document!(prefix, id)

    case transition_fn.(prefix, doc, user) do
      {:ok, _updated} ->
        conn
        |> put_flash(:info, success_msg)
        |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "This transition is not allowed in the current state.")
        |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}")
    end
  end
end
