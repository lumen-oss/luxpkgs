defmodule Luxpkgs.Repo.Migrations.AddAvatarSourceToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :avatar_source, :string
    end
  end
end
