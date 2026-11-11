defmodule Luxpkgs.Repo.Migrations.AddMetadataToReleases do
  use Ecto.Migration

  def change do
    alter table(:releases) do
      add :metadata, :map, default: %{}, null: false
    end
  end
end
