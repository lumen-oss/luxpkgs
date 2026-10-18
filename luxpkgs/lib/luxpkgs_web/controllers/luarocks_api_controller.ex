defmodule LuxpkgsWeb.LuaRocksApiController do
  use LuxpkgsWeb, :controller

  alias Luxpkgs.Packages
  alias Luxpkgs.Packages.Package
  alias Luxpkgs.Accounts

  action_fallback LuxpkgsWeb.FallbackController

  defp verify_key(conn, _params) do
    case Guardian.Plug.current_resource(conn) do
      %Accounts.Scope{} = scope -> {:ok, scope}
      _ -> {:error, :unauthorized}
    end
  end

  defp with_auth(conn, fun) do
    case verify_key(conn, conn.params) do
      {:ok, scope} -> fun.(conn, scope)
      {:error, :unauthorized} -> render_unauthorized(conn)
    end
  end

  defp render_unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{errors: ["Invalid key"]})
  end

  defp check_tfa(%{require_tfa: false}, _params), do: :ok

  defp check_tfa(scope, params) do
    if LuxpkgsWeb.RateLimit.totp_exceeded?(scope.user.id) do
      {:error, :tfa_required}
    else
      case Luxpkgs.Accounts.TOTP.verify(scope.user, params["tfa_code"]) do
        :ok -> :ok
        :error -> {:error, :tfa_required}
      end
    end
  end

  # Luarocks always expects 1.0.0 here - stub.
  def tool_version(conn, _params) do
    json(conn, %{version: "1.0.0"})
  end

  def status(conn, _params) do
    with_auth(conn, fn conn, _ ->
      # NOTE(vhyrro): luarocks theoretically expects a user ID and created_at ID, but it never uses these values.
      # In order not to leak the user's ID nor account creation data, we just return an empty table.
      json(conn, %{})
    end)
  end

  def check_rockspec(conn, %{"package" => package_name, "version" => version}) do
    with_auth(conn, fn conn, scope ->
      package_name = String.downcase(package_name)
      version = String.downcase(version)

      module = Packages.get_package_by_user_and_name(scope.user, package_name)

      version_result =
        case module do
          nil -> nil
          %Package{} = mod -> Packages.get_release_by_package_and_version(mod, version)
        end

      json(conn, %{
        module: if(module, do: %{id: module.id, name: module.name}),
        version:
          if(version_result,
            do: %{
              id: version_result.id,
              version_name: to_string(version_result.version),
              module_id: version_result.package_id
            }
          )
      })
    end)
  end

  def check_rockspec(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{errors: ["Missing required parameters: package, version"]})
  end

  def upload(conn, %{"rockspec_file" => %Plug.Upload{} = file}) do
    with_auth(conn, fn conn, scope ->
      with :ok <- check_tfa(scope, conn.params),
           {:ok, rockspec_text} <- File.read(file.path),
           {:ok, spec} <- parse_rockspec(rockspec_text),
           {:ok, package, release, is_new} <- upload(scope, spec, rockspec_text) do
        json(conn, %{
          module: %{id: package.id, name: package.name, current_version_id: release.id},
          version: %{
            id: release.id,
            version_name: to_string(release.version),
            module_id: package.id
          },
          module_url: "",
          manifests: [],
          is_new: is_new
        })
      else
        {:error, :tfa_required} ->
          {:error, :tfa_required}

        {:error, :invalid_rockspec} ->
          conn
          |> put_status(:bad_request)
          |> json(%{errors: ["Invalid rockspec"]})

        {:error, :verifier_unavailable} ->
          conn
          |> put_status(:service_unavailable)
          |> json(%{errors: ["Rockspec verifier service is unavailable"]})

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:bad_request)
          |> json(%{
            errors: Enum.map(changeset.errors, fn {field, {msg, _}} -> "#{field} #{msg}" end)
          })

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{errors: [to_string(reason)]})
      end
    end)
  end

  def upload(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{errors: ["Missing rockspec_file parameter"]})
  end

  # Since luxpkgs doesn't support code upload yet, we leave this as a stub.
  def upload_rock(conn, %{"version_id" => _version_id}) do
    with_auth(conn, fn conn, _scope ->
      json(conn, %{})
    end)
  end

  defp parse_rockspec(rockspec_text) do
    endpoint = Application.get_env(:luxpkgs, :rockspec_parse_endpoint)

    case Req.post(endpoint, json: %{rockspec: rockspec_text}) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok,
         %{
           package: body["package"],
           version: body["version"],
           summary: body["summary"],
           description: body["description"]
         }}

      {:ok, %Req.Response{status: 422}} ->
        {:error, :invalid_rockspec}

      {:error, _} ->
        {:error, :verifier_unavailable}
    end
  end

  defp upload(scope, spec, rockspec_text) do
    alias Ecto.Multi

    package_name_lower = String.downcase(spec.package)

    result =
      Multi.new()
      |> Multi.run(:package, fn _repo, _changes ->
        case Packages.get_package(package_name_lower) do
          %Package{} = package ->
            if package.user_id == scope.user.id do
              {:ok, package}
            else
              {:error, "Module already exists and is owned by another user"}
            end

          nil ->
            Packages.create_package(scope, %{
              "name" => spec.package,
              "summary" => spec.summary || spec.package,
              "description" => spec.description || ""
            })
        end
      end)
      |> Multi.run(:is_new, fn _repo, %{package: package} ->
        {:ok, is_new_package?(package)}
      end)
      |> Multi.run(:release, fn _repo, %{package: package} ->
        rockspec_path = "#{spec.package}-#{spec.version}.rockspec"

        release =
          %Luxpkgs.Packages.Release{}
          |> Luxpkgs.Packages.Release.changeset(%{
            "version" => spec.version,
            "rockspec" => rockspec_text,
            "package" => spec.package
          })
          |> Ecto.Changeset.put_change(:rockspec_path, rockspec_path)

        case Luxpkgs.Repo.insert(release |> Ecto.Changeset.put_assoc(:package, package)) do
          {:ok, release} -> {:ok, release}
          {:error, changeset} -> {:error, changeset}
        end
      end)
      |> Luxpkgs.Repo.transaction()

    case result do
      {:ok, %{package: package, release: release, is_new: is_new}} ->
        case store_rockspec_file(spec, rockspec_text) do
          :ok -> {:ok, package, release, is_new}
          {:error, reason} -> {:error, reason}
        end

      {:error, :release, %Ecto.Changeset{} = changeset, _} ->
        {:error, changeset}

      {:error, :package, reason, _} ->
        {:error, reason}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp store_rockspec_file(spec, rockspec_text) do
    safe_package = Path.basename(spec.package)
    safe_version = Path.basename(spec.version)

    destination =
      Application.get_env(:luxpkgs, :rockspec_storage)
      |> Path.join("#{safe_package}-#{safe_version}.rockspec")
      |> Path.expand()

    case File.write(destination, rockspec_text) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to store rockspec: #{inspect(reason)}"}
    end
  end

  defp is_new_package?(%Package{releases: []}), do: true
  defp is_new_package?(%Package{}), do: false
end
