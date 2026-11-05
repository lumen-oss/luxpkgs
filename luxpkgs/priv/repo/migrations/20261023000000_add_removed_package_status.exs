defmodule Luxpkgs.Repo.Migrations.AddRemovedPackageStatus do
  use Ecto.Migration

  def up do
    drop constraint(:packages, :packages_status_must_be_valid)

    create constraint(
             :packages,
             :packages_status_must_be_valid,
             check: "status IN ('active', 'hidden', 'removed')"
           )
  end

  def down do
    drop constraint(:packages, :packages_status_must_be_valid)

    create constraint(
             :packages,
             :packages_status_must_be_valid,
             check: "status IN ('active', 'hidden')"
           )
  end
end
