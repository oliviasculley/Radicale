defmodule Calex.Accounts do
  @moduledoc """
  Registration, sessions, email confirmation, password reset, and two-factor login.
  """

  import Ecto.Query
  alias Calex.Accounts.{Invites, TwoFactor, User, UserToken}
  alias Calex.{Email, Mailer, Repo}

  @email_send_limit 5
  @email_send_window_minutes 10

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if User.valid_password?(user, password), do: user
  end

  def get_user!(id), do: Repo.get!(User, id)

  def register_user(attrs, invite_token \\ nil) do
    Ecto.Multi.new()
    |> Ecto.Multi.one(:users_count, from(u in User, select: count(u.id)))
    |> Ecto.Multi.run(:use_invite, fn _repo, _changes ->
      if allow_registration?() and !invite_token do
        {:ok, nil}
      else
        Invites.use_invite(invite_token)
      end
    end)
    |> Ecto.Multi.insert(:add_user, fn %{users_count: count, use_invite: invite} ->
      role = if count == 0, do: :admin, else: :user

      attrs
      |> User.registration_changeset(invite)
      |> User.role_changeset(role)
      |> maybe_confirm_on_registration()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{add_user: user}} -> {:ok, user}
      {:error, :use_invite, :invalid_token, _changes} -> {:error, :invalid_token}
      {:error, :add_user, changeset, _changes} -> {:error, changeset}
    end
  end

  def change_user_registration(attrs \\ %{}) do
    User.registration_changeset(attrs, nil, hash_password: false)
  end

  def change_user_email(user, attrs \\ %{}), do: User.email_changeset(user, attrs)

  def change_user_password(user, attrs \\ %{}),
    do: User.password_changeset(user, attrs, hash_password: false)

  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{} = email_token <- Repo.one(query),
         {:ok, %{user: user}} <-
           Repo.transaction(user_email_multi(user, email_token.sent_to, context)) do
      {:ok, user}
    else
      _error -> :error
    end
  end

  def deliver_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    if email_disabled?() do
      {:error, :email_disabled}
    else
      {encoded_token, user_token} =
        UserToken.build_email_token(%{user | email: current_email}, "change:#{current_email}")

      Repo.insert!(%{user_token | sent_to: user.email})

      deliver(
        Email.update_email(%{user | email: user.email}, update_email_url_fun.(encoded_token))
      )
    end
  end

  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _changes} -> {:error, changeset}
    end
  end

  def update_user_locale(user, locale) do
    user |> User.locale_changeset(locale) |> Repo.update()
  end

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "session"))
    :ok
  end

  def allow_registration? do
    registration_mode() == :public or admin_count() == 0
  end

  def registration_mode do
    case Application.get_env(:calex, __MODULE__)[:registration] do
      "public" -> :public
      _other -> :invite_only
    end
  end

  def admin?(%User{role: :admin}), do: true
  def admin?(%User{}), do: false

  def email_disabled? do
    Application.get_env(:calex, :email_disabled, false) == true
  end

  def password_reset_offered? do
    not email_disabled?() or sole_administrator?()
  end

  def sole_administrator? do
    admin_count() == 1
  end

  def confirm_when_email_disabled(%User{confirmed_at: confirmed} = user)
      when not is_nil(confirmed) do
    user
  end

  def confirm_when_email_disabled(%User{} = user) do
    if email_disabled?() do
      user |> User.confirm_changeset() |> Repo.update!()
    else
      user
    end
  end

  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    cond do
      email_disabled?() ->
        {:error, :email_disabled}

      user.confirmed_at ->
        {:error, :already_confirmed}

      true ->
        {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
        Repo.insert!(user_token)
        deliver(Email.welcome(user, confirmation_url_fun.(encoded_token)))
    end
  end

  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _error -> :error
    end
  end

  def confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, ["confirm"]))
  end

  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    if email_disabled?() and not sole_administrator?() do
      {:error, :email_disabled}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
      Repo.insert!(user_token)
      url = reset_password_url_fun.(encoded_token)

      if email_disabled?() do
        require Logger
        Logger.warning("password reset for the only administrator: #{url}")
        {:ok, :logged}
      else
        deliver(Email.reset_password(user, url))
      end
    end
  end

  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _error -> nil
    end
  end

  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _changes} -> {:error, changeset}
    end
  end

  def deliver_two_factor_email_code(%User{} = user) do
    if email_disabled?() do
      {:error, :email_disabled}
    else
      enqueue_two_factor_email_code(user)
    end
  end

  def enable_app_two_factor(user, password, secret, code, opts \\ []) do
    with :ok <- ensure_can_enable_two_factor(user, password),
         {:ok, used_at} <- TwoFactor.totp_used_at(secret, TwoFactor.normalize_code(code)) do
      enable_two_factor(user, opts,
        two_factor_method: :app,
        totp_secret: secret,
        totp_last_used_at: used_at
      )
    else
      {:error, reason} -> {:error, reason}
      :error -> {:error, :invalid_code}
    end
  end

  def enable_email_two_factor(user, password, code, opts \\ []) do
    if email_disabled?() do
      {:error, :email_disabled}
    else
      with :ok <- ensure_can_enable_two_factor(user, password),
           :ok <- verify_two_factor_email_code(user, code) do
        enable_two_factor(user, opts,
          two_factor_method: :email,
          totp_secret: nil,
          totp_last_used_at: nil
        )
      end
    end
  end

  def disable_two_factor(user, password) do
    cond do
      not User.valid_password?(user, password) ->
        {:error, :invalid_password}

      not User.two_factor_enabled?(user) ->
        {:ok, user}

      true ->
        user
        |> Ecto.Changeset.change(two_factor_method: nil, totp_secret: nil, totp_last_used_at: nil)
        |> Repo.update()
        |> case do
          {:ok, user} ->
            Repo.delete_all(UserToken.user_and_contexts_query(user, ["two_factor_recovery"]))
            {:ok, user}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def regenerate_two_factor_recovery_codes(user, password) do
    cond do
      not User.two_factor_enabled?(user) ->
        {:error, :not_enabled}

      not User.valid_password?(user, password) ->
        {:error, :invalid_password}

      true ->
        Repo.transaction(fn ->
          Repo.delete_all(UserToken.user_and_contexts_query(user, ["two_factor_recovery"]))
          insert_recovery_codes(user)
        end)
    end
  end

  def count_two_factor_recovery_codes(user) do
    Repo.aggregate(
      from(t in UserToken, where: t.user_id == ^user.id and t.context == "two_factor_recovery"),
      :count
    )
  end

  def verify_two_factor_login(%User{two_factor_method: nil}, _code) do
    {:error, :invalid_code}
  end

  def verify_two_factor_login(%User{} = user, code) when is_binary(code) do
    case verify_primary_two_factor(user, code) do
      {:ok, user} -> {:ok, user}
      {:error, :invalid_code} -> verify_recovery_code(user, code)
    end
  end

  def verify_two_factor_login(_user, _code), do: {:error, :invalid_code}

  def verify_recovery_code(user, code) do
    case Repo.delete_all(UserToken.verify_two_factor_recovery_code_query(user, code)) do
      {n, _deleted} when n > 0 -> {:ok, user}
      {0, _deleted} -> {:error, :invalid_code}
    end
  end

  defp maybe_confirm_on_registration(changeset) do
    if email_disabled?(), do: User.confirm_changeset(changeset), else: changeset
  end

  defp admin_count do
    Repo.aggregate(from(user in User, where: user.role == :admin), :count)
  end

  defp user_email_multi(user, email, context) do
    changeset = user |> User.email_changeset(%{email: email}) |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, [context]))
  end

  defp enqueue_two_factor_email_code(user) do
    Repo.transaction(fn ->
      Repo.delete_all(
        UserToken.stale_two_factor_email_tokens_query(user, @email_send_window_minutes)
      )

      recent =
        Repo.aggregate(
          UserToken.recent_two_factor_email_tokens_query(user, @email_send_window_minutes),
          :count
        )

      if recent >= @email_send_limit do
        Repo.rollback(:too_many_codes)
      else
        code = TwoFactor.generate_email_code()
        Repo.insert!(UserToken.build_two_factor_email_token(user, code))
        deliver(Email.two_factor(user, code))
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_can_enable_two_factor(user, password) do
    cond do
      User.two_factor_enabled?(user) -> {:error, :already_enabled}
      is_nil(user.confirmed_at) and not email_disabled?() -> {:error, :unconfirmed_email}
      not User.valid_password?(user, password) -> {:error, :invalid_password}
      true -> :ok
    end
  end

  defp enable_two_factor(user, opts, fields) do
    keep_session_token = Keyword.get(opts, :keep_session_token)

    Repo.transaction(fn ->
      user = Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE")
      if user.two_factor_method, do: Repo.rollback(:already_enabled)
      user = user |> Ecto.Changeset.change(fields) |> Repo.update!()
      codes = insert_recovery_codes(user)
      revoke_other_session_tokens(user, keep_session_token)
      {user, codes}
    end)
    |> case do
      {:ok, {user, codes}} -> {:ok, user, codes}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_recovery_codes(user) do
    codes = TwoFactor.generate_recovery_codes()

    Enum.each(codes, fn code ->
      Repo.insert!(UserToken.build_two_factor_recovery_token(user, code))
    end)

    codes
  end

  defp revoke_other_session_tokens(_user, :keep_all), do: :ok

  defp revoke_other_session_tokens(user, nil) do
    Repo.delete_all(from t in UserToken, where: t.user_id == ^user.id and t.context == "session")
  end

  defp revoke_other_session_tokens(user, keep) when is_binary(keep) do
    Repo.delete_all(
      from t in UserToken,
        where: t.user_id == ^user.id and t.context == "session" and t.token != ^keep
    )
  end

  defp verify_primary_two_factor(%User{two_factor_method: :app} = user, code),
    do: verify_app_code(user, code)

  defp verify_primary_two_factor(%User{two_factor_method: :email} = user, code) do
    case verify_two_factor_email_code(user, code) do
      :ok -> {:ok, user}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_primary_two_factor(_user, _code), do: {:error, :invalid_code}

  defp verify_app_code(user, code) do
    last_used = user.totp_last_used_at

    case TwoFactor.totp_used_at(user.totp_secret, TwoFactor.normalize_code(code),
           since: last_used
         ) do
      {:ok, used_at} ->
        {count, _} =
          from(u in User,
            where: u.id == ^user.id,
            where: is_nil(u.totp_last_used_at) or u.totp_last_used_at == ^last_used
          )
          |> Repo.update_all(set: [totp_last_used_at: used_at])

        if count == 1,
          do: {:ok, %{user | totp_last_used_at: used_at}},
          else: {:error, :invalid_code}

      :error ->
        {:error, :invalid_code}
    end
  end

  defp verify_two_factor_email_code(user, code) do
    Repo.transaction(fn ->
      case Repo.delete_all(UserToken.verify_two_factor_email_code_query(user, code)) do
        {n, _} when n > 0 ->
          Repo.delete_all(UserToken.user_and_contexts_query(user, ["two_factor_email"]))
          :verified

        {0, _} ->
          Repo.rollback(:invalid_code)
      end
    end)
    |> case do
      {:ok, :verified} -> :ok
      {:error, :invalid_code} -> {:error, :invalid_code}
    end
  end

  defp deliver(email) do
    case Mailer.deliver(email) do
      {:ok, delivered} -> delivered
      {:error, reason} -> raise "email delivery failed: #{inspect(reason)}"
    end
  end
end
