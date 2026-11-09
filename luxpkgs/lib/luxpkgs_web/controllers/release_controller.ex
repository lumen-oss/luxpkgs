defmodule LuxpkgsWeb.ReleaseController do
  use LuxpkgsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Luxpkgs.Packages.Package
  alias Luxpkgs.Packages
  alias Luxpkgs.Packages.Release

  action_fallback(LuxpkgsWeb.FallbackController)

  operation(:index,
    summary: "List package releases",
    description: "Get all releases for a specific package",
    parameters: [
      package: [
        in: :query,
        description: "Package name",
        type: :string,
        required: true,
        example: "lua-cjson"
      ]
    ],
    responses: %{
      200 =>
        {"Package releases", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{
             data: %OpenApiSpex.Schema{
               type: :array,
               items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/Release"}
             }
           }
         }},
      404 =>
        {"Package not found", "application/json",
         %OpenApiSpex.Reference{"$ref": "#/components/schemas/Error"}}
    }
  )

  def index(conn, %{"package" => package_name}) when is_binary(package_name) do
    case Packages.get_package(package_name) do
      nil -> {:error, :not_found}
      package -> render(conn, :index, releases: package.releases)
    end
  end

  operation(:create,
    summary: "Create a new release",
    description: "Upload a new release for an existing package",
    request_body:
      {"Release data with rockspec file", "multipart/form-data",
       %OpenApiSpex.Reference{"$ref": "#/components/schemas/ReleaseInput"}},
    responses: %{
      201 =>
        {"Release created successfully", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{
             data: %OpenApiSpex.Reference{"$ref": "#/components/schemas/Release"}
           }
         }},
      404 =>
        {"Package not found", "application/json",
         %OpenApiSpex.Reference{"$ref": "#/components/schemas/Error"}},
      400 =>
        {"Invalid rockspec file", "application/json",
         %OpenApiSpex.Reference{"$ref": "#/components/schemas/Error"}},
      422 =>
        {"Validation errors", "application/json",
         %OpenApiSpex.Reference{"$ref": "#/components/schemas/ValidationError"}},
      401 =>
        {"Authentication required", "application/json",
         %OpenApiSpex.Reference{"$ref": "#/components/schemas/Error"}}
    },
    security: [%{"ApiKeyAuth" => []}]
  )

  def create(
        conn,
        %{
          "package" => package_name,
          "version" => _,
          "rockspec" => %Plug.Upload{} = rockspec
        } = release_params
      ) do
    scope = conn.assigns.current_scope

    if scope.require_tfa do
      cond do
        LuxpkgsWeb.RateLimit.totp_exceeded?(scope.user.id) ->
          {:error, :tfa_required}

        release_params["tfa_code"] in [nil, ""] ->
          {:error, :tfa_required}

        Luxpkgs.Accounts.TOTP.verify(scope.user, release_params["tfa_code"]) == :ok ->
          create_release(conn, package_name, release_params, rockspec)

        true ->
          {:error, :tfa_invalid}
      end
    else
      create_release(conn, package_name, release_params, rockspec)
    end
  end

  defp create_release(conn, package_name, release_params, rockspec) do
    if Path.extname(rockspec.filename) == ".rockspec" do
      case Packages.get_package(package_name) do
        nil ->
          {:error, :not_found}

        %Package{} = package ->
          case Packages.add_release(conn.assigns.current_scope, package, release_params) do
            {:ok, %Release{} = release} ->
              conn
              |> put_status(:created)
              |> put_resp_header("location", ~p"/api/releases/#{release.id}")
              |> render(:show, release: release)

            {:error, _} = ret ->
              ret
          end
      end
    else
      {:error, :invalid_rockspec}
    end
  end

  operation(:show,
    summary: "Download a release",
    description: "Download the rockspec file for a specific release",
    parameters: [
      id: [
        in: :path,
        description: "Release ID",
        type: :integer,
        required: true,
        example: 1
      ]
    ],
    responses: %{
      200 =>
        {"Rockspec file", "application/octet-stream",
         %OpenApiSpex.Schema{type: :string, format: :binary}},
      404 =>
        {"Release not found", "application/json",
         %OpenApiSpex.Reference{"$ref": "#/components/schemas/Error"}}
    }
  )

  def show(conn, %{"id" => id}) do
    case Packages.get_public_release(id) do
      %Release{rockspec_path: rockspec_path} = release
      when is_binary(rockspec_path) ->
        safe_rockspec_path = Path.basename(rockspec_path)

        full_file_path =
          Application.get_env(:luxpkgs, :rockspec_storage)
          |> Path.join("/#{safe_rockspec_path}")
          |> Path.expand()

        Packages.increment_release_download_count(release)

        conn
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"#{release.rockspec_path}\""
        )
        |> put_resp_content_type(MIME.from_path(full_file_path) || "application/octet-stream")
        |> send_file(200, full_file_path)

      _ ->
        {:error, :not_found}
    end
  end
end
