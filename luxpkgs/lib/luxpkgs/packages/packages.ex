defmodule Luxpkgs.Packages do
  @moduledoc """
  The Packages context.
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias Luxpkgs.Accounts.User
  alias Luxpkgs.Audit
  alias Luxpkgs.Repo

  alias Luxpkgs.Packages.Package
  alias Luxpkgs.Accounts.Scope

  require Logger

  @doc """
  Subscribes to scoped notifications about any package changes.

  The broadcasted messages match the pattern:

    * {:created, %Package{}}
    * {:updated, %Package{}}

  """
  def subscribe_packages(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Luxpkgs.PubSub, "user:#{key}:packages")
  end

  defp broadcast(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Luxpkgs.PubSub, "user:#{key}:packages", message)
  end

  @doc """
  Restricts a package query to public, active packages.
  """
  def visible(query \\ Package) do
    where(query, [p], p.status == :active)
  end

  @doc """
  Returns a paginated list of packages using Flop.
  """
  def list_packages_paginated(flop_params \\ %{}) do
    case Package
         |> visible()
         |> preload(:releases)
         |> Flop.validate_and_run(flop_params, for: Package) do
      {:ok, {packages, meta}} ->
        sorted_packages = Enum.map(packages, &sort_releases/1)
        {:ok, {sorted_packages, meta}}

      error ->
        error
    end
  end

  @doc """
  Returns the total download count across all packages published by the
  given user.
  """
  def total_downloads_by_user(%User{id: user_id}) do
    Package
    |> join(:left, [p], r in Luxpkgs.Packages.Release, on: r.package_id == p.id)
    |> where([p], p.user_id == ^user_id and p.status == :active)
    |> select([_p, r], coalesce(sum(r.download_count), 0))
    |> Repo.one()
  end

  @doc """
  Returns the most popular packages ordered by total downloads.

  ## Examples

      iex> list_featured()
      [%Package{}, ...]

      iex> list_featured(8)
      [%Package{}, ...]
  """
  def list_featured(limit \\ 4) do
    Package
    |> visible()
    |> join(:left, [p], r in Luxpkgs.Packages.Release, on: r.package_id == p.id)
    |> group_by([p], p.id)
    |> order_by([p, r], desc: fragment("COALESCE(SUM(?), 0)", r.download_count))
    |> limit(^limit)
    |> preload(:releases)
    |> Repo.all()
    |> Enum.map(&sort_releases/1)
  end

  @doc """
  Returns the list of packages with a given search query.
  Results are cached for 5 minutes to avoid repeated expensive queries.
  """
  def list_packages(:exact, query, opts) when is_binary(query) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 20) |> min(50)
    cache_key = "search:#{String.downcase(query)}"

    case Cachex.fetch(:search_cache, cache_key, fn _key ->
           results =
             Package
             |> visible()
             |> where([p], ilike(p.name, ^"%#{query}%"))
             |> preload(:releases)
             |> Repo.all()
             |> Enum.map(&sort_releases/1)

           {:commit, results, ttl: :timer.minutes(5)}
         end) do
      {:ok, results} ->
        paginate(results, page, page_size)

      {:commit, results, _opts} ->
        paginate(results, page, page_size)

      {:commit, results} ->
        paginate(results, page, page_size)

      _ ->
        paginate([], page, page_size)
    end
  end

  def list_packages(:fuzzy, _query, _opts) do
    raise "Not yet implemented"
  end

  defp paginate(results, page, page_size) do
    offset = (page - 1) * page_size
    page_results = results |> Enum.drop(offset) |> Enum.take(page_size)

    %{
      packages: page_results,
      total_count: length(results),
      page: page,
      page_size: page_size,
      total_pages: ceil(length(results) / page_size)
    }
  end

  @doc """
  Gets a single package.

  Raises `Ecto.NoResultsError` if the Package does not exist.
  """
  def get_package!(name) do
    Package
    |> visible()
    |> Repo.get_by!(name: name)
    |> Repo.preload(:releases)
    |> sort_releases()
  end

  def get_package(name) do
    case Package |> visible() |> Repo.get_by(name: name) do
      nil ->
        nil

      package ->
        package
        |> Repo.preload(:releases)
        |> sort_releases()
    end
  end

  def get_package_any!(name) do
    Repo.get_by!(Package, name: name)
    |> Repo.preload(:releases)
    |> sort_releases()
  end

  def get_package_any(name) do
    case Repo.get_by(Package, name: name) do
      nil ->
        nil

      package ->
        package
        |> Repo.preload(:releases)
        |> sort_releases()
    end
  end

  @doc """
  Gets a single package.

  Raises `Ecto.NoResultsError` if the Package does not exist.
  """
  def get_package_by_id!(id) do
    Repo.get_by!(Package, id: id)
    |> Repo.preload(:releases)
    |> sort_releases()
  end

  def get_package_by_id(id) do
    case Repo.get_by(Package, id: id) do
      nil ->
        nil

      package ->
        package
        |> Repo.preload(:releases)
        |> sort_releases()
    end
  end

  @doc """
  Creates a package.
  """
  def create_package(
        %Scope{} = scope,
        %{"name" => _} = attrs
      ) do
    if has_permission?(scope, attrs) do
      with {:ok, package = %Package{}} <-
             %Package{}
             |> Package.changeset(attrs, scope)
             |> Repo.insert() do
        package = Repo.preload(package, :releases)
        broadcast(scope, {:created, package})
        {:ok, package}
      else
        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :insufficient_permissions}
    end
  end

  def create_package(_, _) do
    {:error, :insufficient_permissions}
  end

  @doc """
  Updates a package.

  ## Examples

      iex> update_package(package, %{field: new_value})
      {:ok, %Package{}}

      iex> update_package(package, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_package(
        %Scope{} = scope,
        %Package{} = package,
        %{summary: _, description: _} = attrs
      ) do
    if has_permission?(scope, package) do
      with {:ok, package = %Package{}} <-
             package
             |> Package.changeset(attrs, scope)
             |> Repo.update() do
        broadcast(scope, {:updated, package})
        {:ok, package}
      end
    else
      {:error, :insufficient_permissions}
    end
  end

  def update_package(_, _) do
    {:error, :insufficient_permissions}
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking package changes.

  ## Examples

      iex> change_package(package)
      %Ecto.Changeset{data: %Package{}}

  """
  def change_package(
        %Scope{} = scope,
        %Package{} = package,
        attrs
      ) do
    if has_permission?(scope, package) do
      Package.changeset(package, attrs, scope)
    else
      Package.changeset(package, attrs, scope)
      |> Ecto.Changeset.add_error(:name, "insufficient permissions to change package")
    end
  end

  def change_package(_, _, _) do
    {:error, :insufficient_permissions}
  end

  alias Luxpkgs.Packages.Release

  @doc """
  Subscribes to scoped notifications about any release changes.

  The broadcasted messages match the pattern:

    * {:created, %Release{}}
    * {:updated, %Release{}}
    * {:deleted, %Release{}}

  """
  def subscribe_releases(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Luxpkgs.PubSub, "user:#{key}:releases")
  end

  @doc """
  Returns the list of releases.

  ## Examples

      iex> list_releases(scope)
      [%Release{}, ...]

  """
  def list_releases(%Package{} = package) do
    Repo.get(Package, package.id)
    |> Repo.preload(:releases)
    |> sort_releases()
    |> Map.get(:releases)
  end

  @doc """
  Returns the highest release that is not yanked, or nil.
  """
  def latest_release(%Package{releases: releases}) when is_list(releases) do
    releases
    |> Enum.reject(& &1.yanked_at)
    |> Enum.sort(fn a, b -> Version.compare(a.version, b.version) != :gt end)
    |> List.last()
  end

  @doc """
  Returns the latest release version as a string, or nil.
  """
  def latest_version(%Package{} = package) do
    case latest_release(package) do
      nil -> nil
      release -> to_string(release.version)
    end
  end

  @doc """
  Gets a single release.

  Raises `Ecto.NoResultsError` if the Release does not exist.

  ## Examples

      iex> get_release!(123)
      %Release{}

      iex> get_release!(456)
      ** (Ecto.NoResultsError)

  """
  def get_release!(id) do
    Repo.get_by!(Release, id: id)
  end

  def get_release(id) do
    Repo.get_by(Release, id: id)
  end

  def get_public_release(id) do
    Release
    |> join(:inner, [r], p in Package, on: p.id == r.package_id)
    |> where([r, p], r.id == ^id and p.status == :active)
    |> Repo.one()
  end

  def get_release_by_package_and_version(%Package{} = package, version) do
    Release
    |> where(package_id: ^package.id, version: ^version)
    |> Repo.one()
  end

  @doc """
  Marks a release as yanked. Owners can yank their own releases; yanked releases
  stay downloadable by exact version but are skipped when resolving the latest version.
  """
  def yank_release(%Scope{} = scope, %Release{} = release),
    do: set_release_yanked(scope, release, true)

  @doc """
  Removes the yanked mark from a release.
  """
  def unyank_release(%Scope{} = scope, %Release{} = release),
    do: set_release_yanked(scope, release, false)

  defp set_release_yanked(%Scope{user: %User{} = user} = scope, %Release{} = release, yanked?) do
    release = Repo.preload(release, :package)
    package = release.package

    cond do
      package.user_id != user.id ->
        {:error, :insufficient_permissions}

      not Scope.package_permitted?(scope, package) ->
        {:error, :insufficient_permissions}

      release.yanked_at != nil == yanked? ->
        {:ok, release}

      true ->
        yanked_at =
          if yanked?, do: DateTime.utc_now() |> DateTime.truncate(:second)

        action = if yanked?, do: "release.yanked", else: "release.unyanked"

        attrs = %{
          type: :package,
          action: action,
          actor_label: user.username || user.email,
          target_type: "release",
          target_id: release.id,
          target_label: "#{package.name} #{release.version}",
          metadata: %{"package_id" => package.id, "version" => to_string(release.version)}
        }

        Multi.new()
        |> Multi.update(:release, Ecto.Changeset.change(release, yanked_at: yanked_at))
        |> Multi.insert(:audit, Audit.changeset(attrs))
        |> Repo.transaction()
        |> case do
          {:ok, %{release: release, audit: event}} ->
            Audit.broadcast(event)
            broadcast(scope, {:updated, release})
            {:ok, release}

          {:error, _step, reason, _changes} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Returns packages owned by the given user, matching by name (case-insensitive).
  """
  def get_package_by_user_and_name(%User{id: user_id}, name) when is_binary(name) do
    name_lower = String.downcase(name)

    Package
    |> visible()
    |> where([p], p.user_id == ^user_id and ilike(p.name, ^name_lower))
    |> preload(:releases)
    |> Repo.one()
    |> case do
      nil -> nil
      package -> sort_releases(package)
    end
  end

  @doc """
  Creates a release.
  """
  def add_release(
        %Scope{} = scope,
        %Package{} = package,
        %{
          "package" => package_name,
          "version" => version,
          "rockspec" => %Plug.Upload{} = rockspec
        } = attrs
      ) do
    if has_permission?(scope, package) do
      case Multi.new()
           |> Multi.insert(
             :release,
             package
             |> Ecto.build_assoc(:releases)
             |> Release.changeset(%{attrs | "rockspec" => File.read!(Path.expand(rockspec.path))})
           )
           |> Multi.run(:copy_rockspec, fn _repo, %{release: release} ->
             safe_package_name = Path.basename(package_name)
             safe_version = Path.basename(version)

             destination_path =
               Application.get_env(:luxpkgs, :rockspec_storage)
               |> Path.join("#{safe_package_name}-#{safe_version}.rockspec")
               |> Path.expand()

             case File.cp(
                    Path.expand(rockspec.path),
                    destination_path
                  ) do
               :ok ->
                 {:ok, release}

               {:error, reason} ->
                 {:error, reason}
             end
           end)
           |> Repo.transaction() do
        {:ok, %{release: release}} ->
          broadcast(scope, {:created, release})
          {:ok, release}

        {:error, :copy_rockspec, reason, _changes} ->
          Logger.error("Failed to copy rockspec file: #{reason}")
          {:error, :file_copy_failed}

        {:error, _step, reason, _changes} ->
          Logger.error("Failed to create release: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, :insufficient_permissions}
    end
  end

  def add_release(_, _, _) do
    {:error, :insufficient_permissions}
  end

  def increment_release_download_count(%Release{id: id}) do
    Release
    |> where([r], r.id == ^id)
    |> Repo.update_all(inc: [download_count: 1])
  end

  # Regular scopes are not allowed to modify or create packages
  defp has_permission?(
         %Scope{user: %User{}, write_restricted: false, package_whitelist: _} =
           scope,
         %{"name" => _} = attrs
       ) do
    Scope.package_permitted?(scope, attrs)
  end

  defp has_permission?(
         %Scope{user: %User{} = user, write_restricted: false, package_whitelist: _} =
           scope,
         %Package{} = package
       ) do
    package.user_id == user.id && Scope.package_permitted?(scope, package)
  end

  defp has_permission?(%Scope{user: %User{}}, %{"name" => _}), do: false
  defp has_permission?(%Scope{user: %User{}}, %Package{}), do: false

  defp has_permission?(%Scope{user: %User{}} = scope, %Release{} = release) do
    release_scope = Scope.for_release(release)

    release_scope == scope && Scope.package_permitted?(scope, release.package)
  end

  defp sort_releases(package = %Package{}) do
    update_in(package.releases, fn releases ->
      Enum.sort(releases, fn r1, r2 ->
        Version.compare(r1.version, r2.version) != :gt
      end)
    end)
  end
end
