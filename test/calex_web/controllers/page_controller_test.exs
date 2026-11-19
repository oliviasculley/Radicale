defmodule CalexWeb.PageControllerTest do
  use CalexWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "calex"
  end
end
