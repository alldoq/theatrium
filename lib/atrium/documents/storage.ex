defmodule Atrium.Documents.Storage do
  @moduledoc """
  Path helpers for encrypted file-document storage.
  """

  def uploads_root do
    Application.fetch_env!(:atrium, :uploads_root)
  end

  def tenant_files_dir(tenant_prefix, document_id) do
    Path.join([uploads_root(), "documents", tenant_prefix, "files", document_id])
  end

  def version_file_path(tenant_prefix, document_id, version) when is_integer(version) do
    Path.join(tenant_files_dir(tenant_prefix, document_id), "v#{version}.enc")
  end

  def relative_storage_path(tenant_prefix, document_id, version) when is_integer(version) do
    Path.join(["documents", tenant_prefix, "files", document_id, "v#{version}.enc"])
  end

  def absolute_from_relative(relative_path) when is_binary(relative_path) do
    Path.join(uploads_root(), relative_path)
  end
end
