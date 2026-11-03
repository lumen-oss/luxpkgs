defmodule Luxpkgs.PackagesTest do
  use Luxpkgs.DataCase

  alias Luxpkgs.Packages

  describe "packages" do
    alias Luxpkgs.Packages.Package

    import Luxpkgs.AccountsFixtures, only: [user_scope_fixture: 0]
    import Luxpkgs.PackagesFixtures

    test "create_package/2 with valid data creates a package" do
      scope = user_scope_fixture()
      valid_attrs = %{"name" => "my-pkg", "summary" => "A package", "description" => "Details"}

      assert {:ok, %Package{} = package} = Packages.create_package(scope, valid_attrs)
      assert package.name == "my-pkg"
      assert package.summary == "A package"
      assert package.user_id == scope.user.id
    end

    test "create_package/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Packages.create_package(scope, %{"name" => nil})
    end

    test "get_package!/1 returns the package by name" do
      scope = user_scope_fixture()
      package = package_fixture(scope)
      assert Packages.get_package!(package.name).id == package.id
    end

    test "get_package!/1 raises for unknown name" do
      assert_raise Ecto.NoResultsError, fn -> Packages.get_package!("nonexistent") end
    end

    test "get_package/1 returns the package by name" do
      scope = user_scope_fixture()
      package = package_fixture(scope)
      assert Packages.get_package(package.name).id == package.id
    end

    test "get_package/1 returns nil for unknown name" do
      refute Packages.get_package("nonexistent")
    end

    test "get_package_by_id!/1 returns the package" do
      scope = user_scope_fixture()
      package = package_fixture(scope)
      assert Packages.get_package_by_id!(package.id).id == package.id
    end

    test "get_package_by_id/1 returns nil for unknown id" do
      refute Packages.get_package_by_id(-1)
    end

    test "update_package/3 with valid data updates the package" do
      scope = user_scope_fixture()
      package = package_fixture(scope)
      update_attrs = %{summary: "Updated summary", description: "Updated description"}

      assert {:ok, %Package{} = package} = Packages.update_package(scope, package, update_attrs)
      assert package.summary == "Updated summary"
      assert package.description == "Updated description"
    end

    test "update_package/3 with invalid scope returns error" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      package = package_fixture(scope)

      assert {:error, :insufficient_permissions} =
               Packages.update_package(other_scope, package, %{summary: "X", description: "Y"})
    end

    test "change_package/3 returns a package changeset" do
      scope = user_scope_fixture()
      package = package_fixture(scope)
      assert %Ecto.Changeset{} = Packages.change_package(scope, package, %{})
    end

    test "list_packages_paginated/1 returns paginated results" do
      scope = user_scope_fixture()
      package_fixture(scope)
      package_fixture(scope)

      assert {:ok, {packages, meta}} = Packages.list_packages_paginated(%{})
      assert length(packages) == 2
      assert meta.total_count == 2
    end
  end

  describe "releases" do
    import Luxpkgs.AccountsFixtures, only: [user_scope_fixture: 0]
    import Luxpkgs.PackagesFixtures

    test "list_releases/1 returns all releases for a package" do
      scope = user_scope_fixture()
      package = package_fixture(scope)
      release = release_fixture(scope, package)

      releases = Packages.list_releases(package)
      assert length(releases) == 1
      assert hd(releases).id == release.id
    end

    test "get_release!/1 returns the release" do
      scope = user_scope_fixture()
      release = release_fixture(scope)

      assert Packages.get_release!(release.id).id == release.id
    end

    test "get_release!/1 raises for unknown id" do
      assert_raise Ecto.NoResultsError, fn -> Packages.get_release!(-1) end
    end

    test "get_release/1 returns the release" do
      scope = user_scope_fixture()
      release = release_fixture(scope)

      assert Packages.get_release(release.id).id == release.id
    end

    test "get_release/1 returns nil for unknown id" do
      refute Packages.get_release(-1)
    end
  end

  alias Luxpkgs.Packages.Release
  alias Luxpkgs.Repo

  defp set_status!(package, status) do
    package
    |> Ecto.Changeset.change(status: status)
    |> Repo.update!()
  end

  describe "visibility" do
    import Luxpkgs.AccountsFixtures, only: [user_scope_fixture: 0]
    import Luxpkgs.PackagesFixtures

    test "get_package/1 hides non-active packages, get_package_any/1 does not" do
      scope = user_scope_fixture()
      package = package_fixture(scope) |> set_status!(:hidden)

      refute Packages.get_package(package.name)
      assert Packages.get_package_any(package.name).id == package.id
      assert Packages.get_package_any!(package.name).id == package.id
    end

    test "list_packages_paginated/1 excludes non-active packages" do
      scope = user_scope_fixture()
      package_fixture(scope)
      package_fixture(scope) |> set_status!(:hidden)
      package_fixture(scope) |> set_status!(:yanked)

      assert {:ok, {packages, meta}} = Packages.list_packages_paginated(%{})
      assert length(packages) == 1
      assert meta.total_count == 1
    end

    test "list_packages/3 excludes non-active packages" do
      scope = user_scope_fixture()
      package = package_fixture(scope) |> set_status!(:hidden)

      assert Packages.list_packages(:exact, package.name, []).packages == []
    end

    test "list_featured/1 excludes non-active packages" do
      scope = user_scope_fixture()
      visible = package_fixture(scope)
      hidden = package_fixture(scope) |> set_status!(:hidden)

      release_fixture(scope, hidden)
      visible_release = release_fixture(scope, visible)
      Packages.increment_release_download_count(visible_release)

      assert [%{name: name}] = Packages.list_featured(4)
      assert name == visible.name
    end

    test "total_downloads_by_user/1 excludes non-active packages" do
      scope = user_scope_fixture()
      hidden = package_fixture(scope) |> set_status!(:hidden)
      release = release_fixture(scope, hidden)
      Packages.increment_release_download_count(release)

      assert Packages.total_downloads_by_user(scope.user) == 0
    end

    test "get_package_by_user_and_name/2 excludes non-active packages" do
      scope = user_scope_fixture()
      package = package_fixture(scope) |> set_status!(:yanked)

      refute Packages.get_package_by_user_and_name(scope.user, package.name)
    end

    test "get_public_release/1 only returns releases of active packages" do
      scope = user_scope_fixture()
      release = release_fixture(scope)
      assert Packages.get_public_release(release.id).id == release.id

      Luxpkgs.Packages.Package |> Repo.get!(release.package_id) |> set_status!(:hidden)
      refute Packages.get_public_release(release.id)
    end

    test "increment_release_download_count/1 increments atomically" do
      scope = user_scope_fixture()
      release = release_fixture(scope)

      Packages.increment_release_download_count(release)
      Packages.increment_release_download_count(release)

      assert Repo.get!(Release, release.id).download_count == 2
    end
  end
end
