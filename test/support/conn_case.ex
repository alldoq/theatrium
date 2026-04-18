defmodule AtriumWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use AtriumWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint AtriumWeb.Endpoint

      use AtriumWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import AtriumWeb.ConnCase
    end
  end

  setup tags do
    # For non-async tests that call Provisioner.provision/1, Triplex runs DDL
    # and tenant migrations via Ecto.Migrator, which spawns `:proc_lib` processes.
    # Those processes cannot check out from a sandboxed connection, so we switch
    # to :auto mode for the duration of non-async tests and restore :manual after.
    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :auto)

      on_exit(fn ->
        # Ensure :auto mode so cleanup queries can run regardless of what
        # the test may have done to the sandbox mode.
        Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :auto)
        # Clean up any records written during the test (Triplex.drop in the
        # test's own on_exit already dropped the schema; we just need the public rows).
        Atrium.Repo.delete_all(Atrium.Tenants.Tenant)
        Atrium.Repo.delete_all(Atrium.SuperAdmins.SuperAdmin)
        Atrium.Repo.delete_all(Atrium.Audit.GlobalEvent)
        Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :manual)
      end)
    else
      Atrium.DataCase.setup_sandbox(tags)
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
