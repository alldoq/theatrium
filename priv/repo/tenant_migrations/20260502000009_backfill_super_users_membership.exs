defmodule Atrium.Repo.TenantMigrations.BackfillSuperUsersMembership do
  use Ecto.Migration

  def up do
    schema = prefix() || "public"

    execute("""
    INSERT INTO #{schema}.memberships (id, user_id, group_id, inserted_at)
    SELECT gen_random_uuid(), u.id, g.id, NOW()
    FROM #{schema}.users u
    CROSS JOIN #{schema}.groups g
    WHERE g.slug = 'super_users'
    ON CONFLICT (user_id, group_id) DO NOTHING
    """)
  end

  def down do
    :ok
  end
end
