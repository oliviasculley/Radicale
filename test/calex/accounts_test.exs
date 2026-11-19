defmodule Calex.AccountsTest do
  use Calex.DataCase, async: false

  alias Calex.Accounts
  alias Calex.Accounts.TwoFactor

  setup do
    accounts = Application.get_env(:calex, Accounts)
    email_disabled = Application.get_env(:calex, :email_disabled)

    on_exit(fn ->
      Application.put_env(:calex, Accounts, accounts)
      Application.put_env(:calex, :email_disabled, email_disabled)
    end)

    :ok
  end

  test "first user is an admin" do
    user = user_fixture()
    assert user.role == :admin
    assert Accounts.admin?(user)
  end

  test "invite-only registration rejects a second user without an invite" do
    Application.put_env(:calex, Accounts, registration: "invite")
    admin = user_fixture()
    assert admin.role == :admin

    assert {:error, :invalid_token} =
             Accounts.register_user(%{"email" => unique_email(), "password" => valid_password()})

    guest = invite_user(admin)
    assert guest.role == :user
    refute Accounts.admin?(guest)
  end

  test "REGISTRATION=public allows open sign-up" do
    Application.put_env(:calex, Accounts, registration: "public")
    assert Accounts.registration_mode() == :public

    admin = user_fixture()
    assert admin.role == :admin

    guest = user_fixture()
    assert guest.role == :user
    assert Accounts.allow_registration?()
  end

  test "TOTP accepts the current code and rejects a wrong code" do
    secret = TwoFactor.generate_totp_secret()
    code = NimbleTOTP.verification_code(secret)

    assert {:ok, _used_at} = TwoFactor.totp_used_at(secret, code)
    assert :error = TwoFactor.totp_used_at(secret, "000000")

    user = user_fixture()

    assert {:ok, user, _codes} =
             Accounts.enable_app_two_factor(user, valid_password(), secret, code)

    past = DateTime.add(DateTime.utc_now(), -120, :second)

    Repo.update_all(from(u in Accounts.User, where: u.id == ^user.id),
      set: [totp_last_used_at: past]
    )

    user = Accounts.get_user!(user.id)
    fresh = NimbleTOTP.verification_code(secret)
    assert {:ok, _user} = Accounts.verify_two_factor_login(user, fresh)
    assert {:error, :invalid_code} = Accounts.verify_two_factor_login(user, "000000")
  end

  test "an emailed one-time code is accepted and then rejected" do
    user = user_fixture()
    {:ok, _sent} = Accounts.deliver_two_factor_email_code(user)
    code = emailed_code()

    assert {:ok, user, _codes} = Accounts.enable_email_two_factor(user, valid_password(), code)
    assert user.two_factor_method == :email

    {:ok, _sent} = Accounts.deliver_two_factor_email_code(user)
    login_code = emailed_code()
    assert {:ok, _user} = Accounts.verify_two_factor_login(user, login_code)
    assert {:error, :invalid_code} = Accounts.verify_two_factor_login(user, login_code)
  end

  test "a recovery code logs in once" do
    user = user_fixture()
    secret = TwoFactor.generate_totp_secret()
    code = NimbleTOTP.verification_code(secret)

    assert {:ok, user, [recovery | _rest]} =
             Accounts.enable_app_two_factor(user, valid_password(), secret, code)

    assert {:ok, _user} = Accounts.verify_two_factor_login(user, recovery)
    assert {:error, :invalid_code} = Accounts.verify_two_factor_login(user, recovery)
  end

  test "mailer config requires SMTP host, username, and password all set or all unset" do
    smtp =
      Calex.Mailer.config_from_env(%{
        "HOST" => "calex.example",
        "SMTP_HOST" => "smtp.example",
        "SMTP_USERNAME" => "mailer",
        "SMTP_PASSWORD" => "secret",
        "EMAIL_FROM" => "calendar@calex.example",
        "EMAIL_NAME" => "calex"
      })

    assert smtp[:adapter] == Swoosh.Adapters.SMTP
    assert smtp[:relay] == "smtp.example"
    assert smtp[:username] == "mailer"
    assert smtp[:password] == "secret"
    assert smtp[:port] == 587
    assert smtp[:email_from] == "calendar@calex.example"
    assert smtp[:email_name] == "calex"

    local = Calex.Mailer.config_from_env(%{"HOST" => "calex.example"})
    assert local[:adapter] == Swoosh.Adapters.Local
    assert local[:email_from] == "no-reply@calex.example"
    assert local[:email_name] == "calex"

    disabled =
      Calex.Mailer.config_from_env(%{
        "HOST" => "calex.example",
        "DISABLE_EMAIL" => "true",
        "SMTP_HOST" => "smtp.example"
      })

    assert disabled[:adapter] == Swoosh.Adapters.Local

    assert_raise RuntimeError, ~r/SMTP_HOST, SMTP_USERNAME, and SMTP_PASSWORD/, fn ->
      Calex.Mailer.config_from_env(%{"HOST" => "calex.example", "SMTP_HOST" => "smtp.example"})
    end
  end

  test "startup does not require a Radicale config, htpasswd, or rights file" do
    assert Calex.Boot.required_files() == []
    assert Calex.Boot.config_sources() == [:environment, :database]

    env = Application.get_all_env(:calex)
    refute Keyword.has_key?(env, :config_path)
    refute Keyword.has_key?(env, :htpasswd)
    refute Keyword.has_key?(env, :rights)
    refute File.exists?(Path.expand("config.ini", File.cwd!()))
  end

  defp emailed_code do
    assert_received {:email, email}
    body = email.text_body |> to_string()
    [_, code] = Regex.run(~r/Your calex code is (\d{6})/, body)
    code
  end
end
