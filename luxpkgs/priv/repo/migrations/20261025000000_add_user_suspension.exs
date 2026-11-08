defmodule Luxpkgs.Repo.Migrations.AddUserSuspension do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :suspended_at, :utc_datetime
      add :suspension_reason, :text
    end

    create index(:users, [:suspended_at],
             where: "suspended_at IS NOT NULL",
             name: :users_suspended_at_index
           )
  end
end
