defmodule Luxpkgs.Packages.ReleaseTest do
  use Luxpkgs.DataCase, async: true

  import Luxpkgs.AccountsFixtures, only: [user_scope_fixture: 0]
  import Luxpkgs.PackagesFixtures

  alias Luxpkgs.Packages.Release
  alias Luxpkgs.Repo

  test "stores metadata on a release" do
    scope = user_scope_fixture()
    package = package_fixture(scope)
    metadata = %{"license" => "MIT", "dependencies" => ["lua >= 5.1"]}

    release = release_fixture(scope, package, metadata: metadata)

    assert Repo.get!(Release, release.id).metadata == metadata
  end

  test "defaults metadata to an empty map" do
    scope = user_scope_fixture()
    package = package_fixture(scope)

    release = release_fixture(scope, package)

    assert Repo.get!(Release, release.id).metadata == %{}
  end
end
