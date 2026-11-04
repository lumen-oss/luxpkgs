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

    test "yank_release/2 marks a release and unyank_release/2 clears it" do
      scope = user_scope_fixture()
      release = release_fixture(scope)

      assert {:ok, yanked} = Packages.yank_release(scope, release)
      assert yanked.yanked_at
      assert Repo.get!(Luxpkgs.Packages.Release, release.id).yanked_at
      assert Enum.any?(Repo.all(Luxpkgs.Audit.Event), &(&1.action == "release.yanked"))

      assert {:ok, unyanked} = Packages.unyank_release(scope, yanked)
      refute unyanked.yanked_at
      assert Enum.any?(Repo.all(Luxpkgs.Audit.Event), &(&1.action == "release.unyanked"))
    end

    test "yank_release/2 rejects non-owners" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      release = release_fixture(scope)

      assert {:error, :insufficient_permissions} = Packages.yank_release(other_scope, release)
      refute Repo.get!(Luxpkgs.Packages.Release, release.id).yanked_at
    end

    test "latest_release/1 skips yanked releases" do
      scope = user_scope_fixture()
      package = package_fixture(scope)
      release_fixture(scope, package, version: "1.0.0")

      release_fixture(scope, package,
        version: "2.0.0",
        yanked_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      package = Packages.get_package!(package.name)
      assert Packages.latest_version(package) == "1.0.0"
      assert Packages.latest_release(package).version == Version.parse!("1.0.0")
    end

    test "yanked releases stay available by exact version" do
      scope = user_scope_fixture()
      package = package_fixture(scope)
      release = release_fixture(scope, package, version: "1.0.0")

      assert {:ok, _yanked} = Packages.yank_release(scope, release)

      package = Packages.get_package!(package.name)

      assert Packages.get_release_by_package_and_version(package, "1.0.0").id == release.id
    end
  end

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
      package_fixture(scope) |> set_status!(:hidden)

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
      package = package_fixture(scope) |> set_status!(:hidden)

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

      assert Repo.get!(Luxpkgs.Packages.Release, release.id).download_count == 2
    end
  end

  describe "moderation" do
    import Luxpkgs.AccountsFixtures, only: [user_scope_fixture: 0]
    import Luxpkgs.AdminFixtures
    import Luxpkgs.PackagesFixtures

    alias Luxpkgs.Packages.Package

    test "hide_package/2 hides the package and records an audit event" do
      scope = user_scope_fixture()
      package = package_fixture(scope)
      admin = admin_fixture(%{role: :moderator})

      assert {:ok, hidden} = Packages.hide_package(admin, package)
      assert hidden.status == :hidden

      assert [event] = Luxpkgs.Audit.list_events()
      assert event.action == "package.hidden"
      assert event.actor_admin_id == admin.id
      assert event.target_id == package.id
    end

    test "hide_package/2 clears the search cache" do
      scope = user_scope_fixture()
      package = package_fixture(scope)
      admin = admin_fixture(%{role: :moderator})

      assert Packages.list_packages(:exact, package.name, []).packages != []
      assert {:ok, _package} = Packages.hide_package(admin, package)
      assert Packages.list_packages(:exact, package.name, []).packages == []
    end

    test "unhide_package/2 makes a hidden package visible again" do
      scope = user_scope_fixture()
      package = package_fixture(scope) |> set_status!(:hidden)
      admin = admin_fixture(%{role: :moderator})

      assert {:ok, active} = Packages.unhide_package(admin, package)
      assert active.status == :active
    end

    test "moderators cannot feature packages" do
      scope = user_scope_fixture()
      package = package_fixture(scope)
      moderator = admin_fixture(%{role: :moderator})

      assert {:error, :insufficient_permissions} = Packages.feature_package(moderator, package)
    end

    test "admins can feature and unfeature packages" do
      scope = user_scope_fixture()
      package = package_fixture(scope)
      admin = admin_fixture(%{role: :admin})

      assert {:ok, featured} = Packages.feature_package(admin, package)
      assert featured.featured_at

      assert {:ok, unfeatured} = Packages.unfeature_package(admin, featured)
      refute unfeatured.featured_at
    end

    test "list_packages_admin/1 filters by search, status and featured" do
      scope = user_scope_fixture()
      active = package_fixture(scope, %{name: "admin_active"})
      hidden = package_fixture(scope, %{name: "admin_hidden"}) |> set_status!(:hidden)
      admin = admin_fixture(%{role: :admin})
      {:ok, featured} = Packages.feature_package(admin, active)

      ids =
        Packages.list_packages_admin(search: scope.user.username).packages
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert ids == Enum.sort([active.id, hidden.id])

      assert [%{id: id}] = Packages.list_packages_admin(status: "hidden").packages
      assert id == hidden.id

      assert [%{id: id}] = Packages.list_packages_admin(featured: "true").packages
      assert id == featured.id

      assert Packages.list_packages_admin(search: "admin_active").total_count == 1
    end
  end
end
