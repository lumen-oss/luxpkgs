defmodule Luxpkgs.PackagesFixtures do
  def package_fixture(scope, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    attrs =
      attrs
      |> Enum.into(%{
        name: "pkg_#{unique}",
        summary: "Summary #{unique}",
        description: "Desc #{unique}"
      })
      |> then(fn map -> Map.new(map, fn {k, v} -> {to_string(k), v} end) end)

    %Luxpkgs.Packages.Package{}
    |> Luxpkgs.Packages.Package.changeset(Map.merge(%{"name" => attrs["name"]}, attrs), scope)
    |> Luxpkgs.Repo.insert!()
  end

  def release_fixture(scope, package \\ nil, attrs \\ %{}) do
    package = package || package_fixture(scope)
    unique = System.unique_integer([:positive])

    version = attrs[:version] || "1.0.#{unique}"
    rockspec_content = attrs[:rockspec] || "return { }"

    safe_name = Path.basename(package.name)
    safe_version = Path.basename(to_string(version))

    storage_path =
      Application.get_env(:luxpkgs, :rockspec_storage)
      |> Path.join("#{safe_name}-#{safe_version}.rockspec")
      |> Path.expand()

    File.mkdir_p!(Path.dirname(storage_path))
    File.write!(storage_path, rockspec_content)

    # Insert directly to bypass external HTTP validation in changeset
    %Luxpkgs.Packages.Release{}
    |> Ecto.Changeset.change(%{
      version: version,
      rockspec_path: "#{safe_name}-#{safe_version}.rockspec",
      package_id: package.id,
      download_count: 0,
      yanked_at: attrs[:yanked_at],
      metadata: attrs[:metadata] || %{}
    })
    |> Luxpkgs.Repo.insert!()
  end

  @doc """
  Creates a package owned by the deleted sentinel account.
  """
  def deleted_owner_package_fixture(attrs \\ %{}) do
    owner = Luxpkgs.AccountsFixtures.user_fixture()
    scope = Luxpkgs.Accounts.Scope.for_user(owner)
    package = package_fixture(scope, attrs)
    sentinel = Luxpkgs.Accounts.deleted_user()

    package
    |> Ecto.Changeset.change(user_id: sentinel.id)
    |> Luxpkgs.Repo.update!()
  end
end
