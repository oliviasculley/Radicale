defmodule Calex.Accounts.UserToken do
  @moduledoc """
  Session, email, and two-factor tokens for a user.
  """

  use Calex, :schema
  import Ecto.Query
  alias Calex.Accounts.{TwoFactor, User}

  @hash_algorithm :sha256
  @rand_size 32
  @two_factor_email_validity_in_minutes 5
  @reset_password_validity_in_days 1
  @confirm_validity_in_days 7
  @change_email_validity_in_days 7
  @session_validity_in_days 60

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :user, User
    timestamps(updated_at: false)
  end

  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token: token, context: "session", user_id: user.id}}
  end

  def verify_session_token_query(token) do
    query =
      from token in token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user

    {:ok, query}
  end

  def build_email_token(user, context) do
    build_hashed_token(user, context, user.email)
  end

  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        days = days_for_context(context)

        query =
          from token in token_and_context_query(hashed_token, context),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^days, "day") and token.sent_to == user.email,
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  def verify_change_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in token_and_context_query(hashed_token, context),
            where: token.inserted_at > ago(@change_email_validity_in_days, "day")

        {:ok, query}

      :error ->
        :error
    end
  end

  def token_and_context_query(token, context) do
    from __MODULE__, where: [token: ^token, context: ^context]
  end

  def user_and_contexts_query(user, :all) do
    from t in __MODULE__, where: t.user_id == ^user.id
  end

  def user_and_contexts_query(user, contexts) when is_list(contexts) do
    from t in __MODULE__, where: t.user_id == ^user.id and t.context in ^contexts
  end

  def build_two_factor_email_token(user, code) do
    %__MODULE__{
      token: email_code_hash(user, code),
      context: "two_factor_email",
      sent_to: user.email,
      user_id: user.id
    }
  end

  def verify_two_factor_email_code_query(user, code) do
    hashed = email_code_hash(user, TwoFactor.normalize_code(code))

    from t in __MODULE__,
      where: t.user_id == ^user.id,
      where: t.context == "two_factor_email",
      where: t.token == ^hashed,
      where: t.sent_to == ^user.email,
      where: t.inserted_at > ago(@two_factor_email_validity_in_minutes, "minute")
  end

  def recent_two_factor_email_tokens_query(user, minutes) do
    from t in __MODULE__,
      where: t.user_id == ^user.id,
      where: t.context == "two_factor_email",
      where: t.sent_to == ^user.email,
      where: t.inserted_at > ago(^minutes, "minute")
  end

  def stale_two_factor_email_tokens_query(user, minutes) do
    from t in __MODULE__,
      where: t.user_id == ^user.id,
      where: t.context == "two_factor_email",
      where: t.inserted_at <= ago(^minutes, "minute")
  end

  def build_two_factor_recovery_token(user, code) do
    %__MODULE__{
      token: recovery_code_hash(user, code),
      context: "two_factor_recovery",
      sent_to: nil,
      user_id: user.id
    }
  end

  def verify_two_factor_recovery_code_query(user, code) do
    from t in __MODULE__,
      where: t.user_id == ^user.id,
      where: t.context == "two_factor_recovery",
      where: t.token == ^recovery_code_hash(user, code)
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{token: hashed_token, context: context, sent_to: sent_to, user_id: user.id}}
  end

  defp days_for_context("confirm"), do: @confirm_validity_in_days
  defp days_for_context("reset_password"), do: @reset_password_validity_in_days
  defp days_for_context(_context), do: @confirm_validity_in_days

  defp email_code_hash(user, code) do
    :crypto.hash(@hash_algorithm, "#{user.id}:#{code}")
  end

  defp recovery_code_hash(user, code) do
    normalized = TwoFactor.normalize_recovery_code(code)
    :crypto.hash(@hash_algorithm, "#{user.id}:#{normalized}")
  end
end
