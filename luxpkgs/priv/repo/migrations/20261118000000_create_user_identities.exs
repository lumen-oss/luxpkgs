defmodule Luxpkgs.Repo.Migrations.CreateUserIdentities do
  use Ecto.Migration

  def up do
    create table(:user_identities) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :uid, :string
      add :username, :string, null: false
      add :aka, :string
      add :avatar_url, :string
      timestamps(type: :utc_datetime)
    end

    flush()

    execute """
    INSERT INTO user_identities (user_id, provider, username, aka, avatar_url, inserted_at, updated_at)
    SELECT id, provider, username, aka, avatar_url, now(), now()
    FROM users
    WHERE provider <> 'deleted'
    """

    create unique_index(:user_identities, [:user_id, :provider])
    create unique_index(:user_identities, [:provider, :uid], where: "uid is not null")
    create unique_index(:user_identities, [:provider, :username])
  end

  def down do
    drop table(:user_identities)
  end
end
