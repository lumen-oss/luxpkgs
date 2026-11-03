defmodule Luxpkgs.Repo.Migrations.AddReleaseYankedAt do
  use Ecto.Migration

  def change do
    alter table(:releases) do
      add :yanked_at, :utc_datetime
    end
  end
end
