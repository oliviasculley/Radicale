defmodule Calex.Accounts.User do
  @moduledoc """
  A calex user.
  """

  use Calex, :schema

  @derive {Inspect, except: [:password, :totp_secret]}

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :current_password, :string, virtual: true, redact: true
    field :confirmed_at, :utc_datetime_usec
    field :role, Ecto.Enum, values: [:admin, :user], default: :user
    field :locale, :string
    field :totp_last_used_at, :utc_datetime_usec
    field :totp_secret, Calex.Encrypted.Binary, redact: true
    field :two_factor_method, Ecto.Enum, values: [:app, :email]

    belongs_to :invite, Calex.Accounts.Invite

    timestamps()
  end

  def registration_changeset(attrs, invite, opts \\ []) do
    %__MODULE__{}
    |> cast(attrs, [:email, :password, :locale])
    |> put_change(:invite_id, invite && invite.id)
    |> validate_email()
    |> validate_password(opts)
  end

  def role_changeset(user, role), do: change(user, role: role)

  def email_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_email()
    |> case do
      %{changes: %{email: _email}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "did not change")
    end
  end

  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  def confirm_changeset(user_or_changeset) do
    change(user_or_changeset, confirmed_at: DateTime.utc_now())
  end

  def locale_changeset(user, locale) do
    user
    |> cast(%{"locale" => locale}, [:locale])
    |> validate_required(:locale)
  end

  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_user, _password) do
    Bcrypt.no_user_verify()
    false
  end

  def validate_current_password(changeset, password) do
    changeset = cast(changeset, %{current_password: password}, [:current_password])

    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end

  def two_factor_enabled?(%__MODULE__{two_factor_method: nil}), do: false
  def two_factor_enabled?(%__MODULE__{}), do: true

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Calex.Repo)
    |> unique_constraint(:email)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 80)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end
end
