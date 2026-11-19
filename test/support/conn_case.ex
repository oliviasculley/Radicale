defmodule CalexWeb.ConnCase do
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
  by setting `use CalexWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint CalexWeb.Endpoint

      use CalexWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Calex.AccountsFixtures
      import CalexWeb.ConnCase
    end
  end

  setup tags do
    Calex.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def log_in_user(conn, user) do
    token = Calex.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  def dav_request(user, method, path, body \\ "") do
    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header(
      "authorization",
      "Basic " <> Base.encode64("#{user.email}:#{Calex.AccountsFixtures.valid_password()}")
    )
    |> Plug.Conn.put_req_header("content-type", "text/calendar")
    |> Phoenix.ConnTest.dispatch(CalexWeb.Endpoint, method, path, body)
  end
end
