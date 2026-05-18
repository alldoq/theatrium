defmodule Atrium.Repo.TenantMigrations.SeedCustomersAcls do
  use Ecto.Migration

  # Triplex sets the migration prefix before running each tenant migration, so
  # `prefix()` (Ecto.Migration.prefix/0) reliably returns this tenant's schema
  # name at runtime. This is the same pattern used by the existing
  # BackfillSuperUsersMembership migration (20260502000009).
  #
  # `ensure_default_acls/1` is idempotent — it iterates SectionRegistry and
  # only inserts ACLs that are missing, so running it multiple times is safe.

  def up do
    schema = prefix() || "public"
    Atrium.Tenants.Seed.ensure_default_acls(schema)
  end

  def down do
    # ACL removal is not automated; the customers section ACLs remain in place.
    :ok
  end
end
