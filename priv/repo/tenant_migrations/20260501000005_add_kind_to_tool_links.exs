defmodule Atrium.Repo.Migrations.AddKindToToolLinks do
  use Ecto.Migration

  def change do
    alter table(:tool_links) do
      add :kind, :string, default: "link", null: false
      add :file_path, :string
      add :file_name, :string
      add :file_size, :integer
    end
  end
end
