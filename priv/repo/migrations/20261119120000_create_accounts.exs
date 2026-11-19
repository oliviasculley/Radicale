defmodule Calex.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :utc_datetime_usec
      add :role, :string, null: false, default: "user"
      add :locale, :string
      add :totp_last_used_at, :utc_datetime_usec
      add :totp_secret, :binary
      add :two_factor_method, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])

    create table(:invites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :token, :string, null: false
      add :uses_left, :integer
      add :disabled_at, :utc_datetime_usec
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:invites, [:token])

    alter table(:users) do
      add :invite_id, references(:invites, type: :binary_id, on_delete: :nilify_all)
    end

    create table(:users_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
