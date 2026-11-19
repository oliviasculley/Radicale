defmodule CalexWeb.UserSessionControllerTest do
  use CalexWeb.ConnCase, async: false

  alias Calex.Accounts
  alias Calex.Accounts.TwoFactor

  test "website password login stops for two-factor", %{conn: conn} do
    user = user_fixture()
    secret = TwoFactor.generate_totp_secret()
    code = NimbleTOTP.verification_code(secret)

    assert {:ok, _user, [recovery | _rest]} =
             Accounts.enable_app_two_factor(user, valid_password(), secret, code)

    conn =
      post(conn, ~p"/users/log_in", %{
        "user" => %{"email" => user.email, "password" => valid_password()}
      })

    assert redirected_to(conn) == ~p"/users/log_in/two_factor"
    refute get_session(conn, :user_token)
    assert get_session(conn, :two_factor_user_id) == user.id

    conn =
      conn
      |> recycle()
      |> post(~p"/users/log_in/two_factor", %{"user" => %{"code" => recovery}})

    assert redirected_to(conn) == ~p"/collections"
    assert get_session(conn, :user_token)
  end
end
