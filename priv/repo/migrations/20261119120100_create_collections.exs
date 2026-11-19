defmodule Calex.Repo.Migrations.CreateCollections do
  use Ecto.Migration

  def change do
    create table(:collections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :display_name, :string, null: false
      add :kind, :string, null: false
      add :sync_token, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:collections, [:owner_id, :kind, :name])

    create table(:items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :collection_id, references(:collections, type: :binary_id, on_delete: :delete_all),
        null: false

      add :href, :string, null: false
      add :uid, :string
      add :component, :string, null: false
      add :data, :text, null: false
      add :etag, :string, null: false
      add :sync_gen, :integer, null: false, default: 0
      add :starts_at, :utc_datetime_usec
      add :ends_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:items, [:collection_id, :href])

    create table(:tombstones, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :collection_id, references(:collections, type: :binary_id, on_delete: :delete_all),
        null: false

      add :href, :string, null: false
      add :sync_gen, :integer, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:tombstones, [:collection_id, :sync_gen])

    create table(:grants, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :collection_id, references(:collections, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :privilege, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:grants, [:collection_id, :user_id])
  end
end
