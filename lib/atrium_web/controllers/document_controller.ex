defmodule AtriumWeb.DocumentController do
  use AtriumWeb, :controller
  alias Atrium.Documents
  alias Atrium.Documents.Document

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: &__MODULE__.section_target/1]
       when action in [:index, :show, :download_pdf]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: &__MODULE__.section_target/1]
       when action in [:new, :create, :edit, :update, :submit, :upload_image]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :approve, target: &__MODULE__.section_target/1]
       when action in [:reject, :approve, :archive]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: &__MODULE__.section_target/1]
       when action in [:create_comment, :delete_comment]

  def section_target(conn), do: {:section, conn.path_params["section_key"]}

  def index(conn, %{"section_key" => section_key} = params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    opts = []
    opts = if s = params["subsection_slug"], do: Keyword.put(opts, :subsection_slug, s), else: opts
    opts = if st = params["status"], do: Keyword.put(opts, :status, st), else: opts
    documents = Documents.list_documents(prefix, section_key, opts)
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, section_key})
    section = Atrium.Authorization.SectionRegistry.get(section_key)
    section_name = if section, do: section.name, else: section_key
    render(conn, :index, documents: documents, section_key: section_key, can_edit: can_edit, section_name: section_name)
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

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(422)
        |> render(:new, changeset: changeset, section_key: section_key)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "An unexpected error occurred.")
        |> redirect(to: ~p"/sections/#{section_key}/documents")
    end
  end

  def show(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    doc = Documents.get_document!(prefix, id)
    versions = Documents.list_versions(prefix, doc.id)
    history = Atrium.Audit.history_for(prefix, "Document", doc.id)
    comments = Documents.list_comments(prefix, doc.id)
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, section_key})
    render(conn, :show,
      document: doc,
      versions: versions,
      history: history,
      comments: comments,
      can_edit: can_edit,
      section_key: section_key,
      current_user: user
    )
  end

  def edit(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    doc = Documents.get_document!(prefix, id)

    if doc.status != "draft" do
      conn
      |> put_flash(:error, "Only draft documents can be edited.")
      |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}")
    else
      changeset = Document.update_changeset(doc, %{})
      render(conn, :edit, document: doc, changeset: changeset, section_key: section_key)
    end
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

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(422)
        |> render(:edit, document: doc, changeset: changeset, section_key: section_key)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "An unexpected error occurred.")
        |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}")
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

  def download_pdf(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    doc = Documents.get_document!(prefix, id)
    html = build_pdf_html(doc)

    tmp = System.tmp_dir!() |> Path.join("atrium_doc_#{System.unique_integer([:positive])}.pdf")
    :ok = ChromicPDF.print_to_pdf({:html, html}, output: tmp)
    pdf_binary = File.read!(tmp)
    File.rm(tmp)

    filename = "#{slugify(doc.title)}.pdf"

    conn
    |> put_resp_content_type("application/pdf")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, pdf_binary)
  end

  def upload_image(conn, %{"section_key" => section_key, "image" => %Plug.Upload{} = upload}) do
    prefix = conn.assigns.tenant_prefix
    dir = Path.join(["priv/uploads/documents", prefix, "images"])
    File.mkdir_p!(dir)
    ext = Path.extname(upload.filename)
    filename = "#{System.unique_integer([:positive])}#{ext}"
    dest = Path.join(dir, filename)
    File.cp!(upload.path, dest)
    url = "/uploads/documents/#{prefix}/images/#{filename}"
    json(conn, %{url: url})
  end

  def upload_image(conn, %{"section_key" => _section_key}) do
    conn
    |> put_status(400)
    |> json(%{error: "No image file provided"})
  end

  def create_comment(conn, %{"section_key" => section_key, "id" => id, "comment" => %{"body" => body}}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Documents.add_comment(prefix, id, %{body: body, author_id: user.id}) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Comment added.")
        |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}" <> "#comments")
      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Comment cannot be blank.")
        |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}" <> "#comments")
    end
  end

  def create_comment(conn, %{"section_key" => section_key, "id" => id}) do
    conn
    |> put_flash(:error, "Comment cannot be blank.")
    |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}" <> "#comments")
  end

  def delete_comment(conn, %{"section_key" => section_key, "id" => id, "cid" => cid}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, section_key})
    comment = Documents.get_comment(prefix, cid)

    cond do
      is_nil(comment) ->
        conn |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}" <> "#comments")
      can_edit || comment.author_id == user.id ->
        Documents.delete_comment(prefix, cid)
        conn
        |> put_flash(:info, "Comment deleted.")
        |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}" <> "#comments")
      true ->
        conn
        |> put_flash(:error, "Not authorised.")
        |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}" <> "#comments")
    end
  end

  defp build_pdf_html(doc) do
    body = doc.body_html || ""

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8" />
      <style>
        body { font-family: Georgia, serif; font-size: 12pt; line-height: 1.8; color: #1a1a1a; margin: 72px 90px; }
        h1 { font-size: 24pt; font-weight: 700; margin: 1.2em 0 .4em; }
        h2 { font-size: 18pt; font-weight: 700; margin: 1.1em 0 .4em; }
        h3 { font-size: 14pt; font-weight: 600; margin: 1em 0 .3em; }
        p  { margin: 0 0 .8em; }
        ul { list-style: disc;    padding-left: 1.6em; margin: .5em 0 .8em; }
        ol { list-style: decimal; padding-left: 1.6em; margin: .5em 0 .8em; }
        li { margin: .25em 0; }
        blockquote { border-left: 3px solid #93c5fd; padding-left: 1em; color: #475569; margin: .8em 0; }
        pre  { background: #f1f5f9; border-radius: 4px; padding: .75em 1em; font-family: monospace; font-size: 10pt; overflow-wrap: break-word; margin: .8em 0; }
        code { background: #f1f5f9; border-radius: 3px; padding: .1em .35em; font-family: monospace; font-size: 10pt; }
        strong { font-weight: 700; }
        em { font-style: italic; }
        .doc-header { border-bottom: 1px solid #e2e8f0; padding-bottom: 16px; margin-bottom: 24px; }
        .doc-header h1 { font-size: 22pt; margin: 0 0 6px; }
        .doc-meta { font-size: 9pt; color: #64748b; }
      </style>
    </head>
    <body>
      <div class="doc-header">
        <h1>#{doc.title}</h1>
        <div class="doc-meta">Version #{doc.current_version} &nbsp;·&nbsp; #{doc.status}</div>
      </div>
      #{body}
    </body>
    </html>
    """
  end

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
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
