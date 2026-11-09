defmodule Luxpkgs.Repo.Migrations.CreateAdmins do
  use Ecto.Migration

  def change do
    create table(:admins) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:admins, [:user_id])
    create index(:admins, [:active])

    create constraint(:admins, :admins_role_must_be_valid,
             check: "role IN ('admin', 'moderator')"
           )
  end
end
