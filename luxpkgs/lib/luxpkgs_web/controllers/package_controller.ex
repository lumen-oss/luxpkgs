defmodule LuxpkgsWeb.PackageController do
  use LuxpkgsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias LuxpkgsWeb.ReleaseController
  alias Luxpkgs.Packages.Release
  alias Luxpkgs.Packages
  alias Luxpkgs.Packages.Package

  action_fallback(LuxpkgsWeb.FallbackController)

  operation(:index,
    summary: "Search packages",
    description: "Search for packages by name or keyword",
    parameters: [
      query: [
        in: :query,
        description: "Search query string",
        type: :string,
        required: true,
        example: "json"
      ],
      page: [
        in: :query,
        description: "Page number (1-indexed)",
        type: :integer,
        example: 1
      ],
      page_size: [
        in: :query,
        description: "Results per page (max 50)",
        type: :integer,
        example: 20
      ]
    ],
    responses: %{
      200 =>
        {"Package search results", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{
             data: %OpenApiSpex.Schema{
               type: :array,
               items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/Package"}
             },
             meta: %OpenApiSpex.Schema{
               type: :object,
               properties: %{
                 total_count: %OpenApiSpex.Schema{type: :integer},
                 page: %OpenApiSpex.Schema{type: :integer},
                 page_size: %OpenApiSpex.Schema{type: :integer},
                 total_pages: %OpenApiSpex.Schema{type: :integer}
               }
             }
           }
         }},
      400 =>
        {"Missing query parameter", "application/json",
         %OpenApiSpex.Reference{"$ref": "#/components/schemas/Error"}},
      429 =>
        {"Rate limit exceeded", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{
             error: %OpenApiSpex.Schema{type: :string, example: "rate_limit_exceeded"},
             retry_after_ms: %OpenApiSpex.Schema{type: :integer}
           }
         }}
    }
  )

  def index(conn, %{"query" => query} = params) when is_binary(query) do
    key = build_search_key(conn)

    case LuxpkgsWeb.RateLimit.hit(:search, key) do
      {:allow, _count} ->
        page =
          case Map.get(params, "page", "1") |> Integer.parse() do
            {n, _} when n > 0 -> n
            _ -> 1
          end

        page_size =
          case Map.get(params, "page_size", "20") |> Integer.parse() do
            {n, _} when n > 0 -> n |> min(50)
            _ -> 20
          end

        %{packages: packages, total_count: total, page: p, page_size: ps, total_pages: tp} =
          Packages.list_packages(:exact, query, page: page, page_size: page_size)

        conn
        |> put_resp_header("x-total-count", to_string(total))
        |> render(:index,
          packages: packages,
          total_count: total,
          page: p,
          page_size: ps,
          total_pages: tp
        )

      {:deny, retry_after} ->
        {:error, :rate_limit_exceeded, retry_after}
    end
  end

  def index(_conn, _params), do: {:error, :no_query_string}

  defp build_search_key(conn) do
    case conn.assigns do
      %{current_scope: %{user: %{id: id}}} -> "user:search:#{id}"
      _ -> "ip:search:#{conn.remote_ip |> :inet.ntoa()}"
    end
  end

  operation(:create,
    summary: "Create a new package",
    description: "Create a new package in the repository",
    request_body:
      {"Package data", "application/json",
       %OpenApiSpex.Schema{
         type: :object,
         properties: %{
           package: %OpenApiSpex.Reference{"$ref": "#/components/schemas/PackageInput"}
         },
         required: [:package]
       }},
    responses: %{
      201 =>
        {"Package created successfully", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{
             data: %OpenApiSpex.Reference{"$ref": "#/components/schemas/Package"}
           }
         }},
      422 =>
        {"Validation errors", "application/json",
         %OpenApiSpex.Reference{"$ref": "#/components/schemas/ValidationError"}},
      401 =>
        {"Authentication required", "application/json",
         %OpenApiSpex.Reference{"$ref": "#/components/schemas/Error"}}
    },
    security: [%{"ApiKeyAuth" => []}]
  )

  def create(conn, %{"package" => package_params}) do
    with {:ok, %Package{} = package} <-
           Packages.create_package(conn.assigns.current_scope, package_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/packages/#{package}")
      |> render(:show, package: package)
    else
      {:error, _} = ret -> ret
    end
  end

  operation(:show,
    summary: "Get a package",
    description: "Retrieve details for a specific package by name",
    parameters: [
      name: [
        in: :path,
        description: "Package name",
        type: :string,
        required: true,
        example: "lua-cjson"
      ]
    ],
    responses: %{
      200 =>
        {"Package details", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{
             data: %OpenApiSpex.Reference{"$ref": "#/components/schemas/Package"}
           }
         }},
      404 =>
        {"Package not found", "application/json",
         %OpenApiSpex.Reference{"$ref": "#/components/schemas/Error"}}
    }
  )

  def show(conn, %{"name" => name}) do
    case Packages.get_package(name) do
      nil -> {:error, :not_found}
      package -> render(conn, :show, package: package)
    end
  end

  operation(:download,
    summary: "Download package release",
    description: "Download the latest release of a package",
    parameters: [
      name: [
        in: :path,
        description: "Package name",
        type: :string,
        required: true,
        example: "lua-cjson"
      ]
    ],
    responses: %{
      200 =>
        {"Rockspec file", "application/octet-stream",
         %OpenApiSpex.Schema{type: :string, format: :binary}},
      404 =>
        {"Package or release not found", "application/json",
         %OpenApiSpex.Reference{"$ref": "#/components/schemas/Error"}}
    }
  )

  operation(:download_version,
    summary: "Download package release version",
    description: "Download a specific version of a package",
    parameters: [
      name: [
        in: :path,
        description: "Package name",
        type: :string,
        required: true,
        example: "lua-cjson"
      ],
      version: [
        in: :path,
        description: "Specific version to download",
        type: :string,
        required: true,
        example: "2.1.0"
      ]
    ],
    responses: %{
      200 =>
        {"Rockspec file", "application/octet-stream",
         %OpenApiSpex.Schema{type: :string, format: :binary}},
      404 =>
        {"Package or release not found", "application/json",
         %OpenApiSpex.Reference{"$ref": "#/components/schemas/Error"}}
    }
  )

  def download_version(conn, %{"name" => name, "version" => version}) do
    case Packages.get_package(name) do
      nil ->
        {:error, :not_found}

      package ->
        case Packages.get_release_by_package_and_version(package, version) do
          nil ->
            {:error, :not_found}

          %Release{} = release ->
            ReleaseController.show(conn, %{"id" => release.id})
        end
    end
  end

  def download(conn, %{"name" => name}) do
    case Packages.get_package(name) do
      nil ->
        {:error, :not_found}

      package ->
        case Packages.latest_release(package) do
          nil ->
            {:error, :not_found}

          %Release{} = release ->
            ReleaseController.show(conn, %{"id" => release.id})
        end
    end
  end
end
