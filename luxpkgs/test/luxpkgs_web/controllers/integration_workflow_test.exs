defmodule LuxpkgsWeb.IntegrationWorkflowTest do
  use LuxpkgsWeb.ConnCase

  import Luxpkgs.PackagesFixtures

  defp rockspec_content(package, version) do
    """
    rockspec_format = "3.0"
    package = "#{package}"
    version = "#{version}"
    source = { url = "http://example.com" }
    description = { summary = "A test package" }
    build = { type = "builtin" }
    """
  end

  setup %{conn: conn} do
    Cachex.clear(:search_cache)

    user = Luxpkgs.AccountsFixtures.user_fixture()
    scope = Luxpkgs.Accounts.Scope.for_user(user)
    conn = conn |> authenticate_api_user(user) |> put_req_header("accept", "application/json")
    {:ok, conn: conn, user: user, scope: scope}
  end

  defp create_rockspec_upload(filename, content) do
    path = Path.join(System.tmp_dir!(), filename)
    File.write!(path, content)
    %Plug.Upload{path: path, filename: filename, content_type: "application/x-rockspec"}
  end

  defp fresh_conn(user \\ nil) do
    conn = build_conn() |> put_req_header("accept", "application/json")
    if user, do: authenticate_api_user(conn, user), else: conn
  end

  describe "package lifecycle" do
    test "create, show and search", %{conn: conn} do
      conn =
        post(conn, ~p"/api/packages",
          package: %{
            name: "my-pkg",
            summary: "A great package",
            description: "Full description"
          }
        )

      assert %{"name" => "my-pkg"} = json_response(conn, 201)["data"]

      show_conn = fresh_conn()
      show_conn = get(show_conn, ~p"/api/packages/my-pkg")

      assert %{"name" => "my-pkg", "summary" => "A great package"} =
               json_response(show_conn, 200)["data"]

      search_conn = fresh_conn()
      search_conn = get(search_conn, ~p"/api/packages?query=my-pkg")
      resp = json_response(search_conn, 200)
      assert resp["data"]["my-pkg"]["summary"] == "A great package"
    end

    test "create package with releases shows sorted releases", %{conn: conn, scope: scope} do
      conn =
        post(conn, ~p"/api/packages",
          package: %{
            name: "rel-pkg",
            summary: "Has releases",
            description: "Desc"
          }
        )

      assert json_response(conn, 201)

      package = Luxpkgs.Packages.get_package!("rel-pkg")
      release_fixture(scope, package, version: "1.0.0")
      release_fixture(scope, package, version: "2.0.0")

      show_conn = fresh_conn()
      show_conn = get(show_conn, ~p"/api/packages/rel-pkg")
      data = json_response(show_conn, 200)["data"]
      assert %{"name" => "rel-pkg"} = data
      versions = Enum.map(data["releases"], & &1["version"])
      assert versions == ["1.0.0", "2.0.0"]
    end

    test "duplicate package name returns 422", %{conn: conn, user: user} do
      attrs = %{package: %{name: "dup-pkg", summary: "S", description: "D"}}
      conn = post(conn, ~p"/api/packages", attrs)
      assert json_response(conn, 201)

      conn2 = fresh_conn(user)
      conn2 = post(conn2, ~p"/api/packages", attrs)
      assert json_response(conn2, 422)["errors"]
    end

    test "invalid name format returns 422", %{conn: conn} do
      conn =
        post(conn, ~p"/api/packages",
          package: %{name: "has spaces!", summary: "S", description: "D"}
        )

      assert json_response(conn, 422)["errors"]
    end

    test "name too long returns 422", %{conn: conn} do
      long_name = String.duplicate("a", 21)

      conn =
        post(conn, ~p"/api/packages", package: %{name: long_name, summary: "S", description: "D"})

      assert json_response(conn, 422)["errors"]
    end

    test "unauthenticated create returns 403" do
      conn = fresh_conn()

      conn =
        post(conn, ~p"/api/packages", package: %{name: "noauth", summary: "S", description: "D"})

      assert json_response(conn, 403)
    end
  end

  describe "release lifecycle" do
    test "upload then download", %{conn: conn, scope: scope} do
      conn =
        post(conn, ~p"/api/packages",
          package: %{
            name: "up-pkg",
            summary: "S",
            description: "D"
          }
        )

      assert json_response(conn, 201)

      upload =
        create_rockspec_upload("up-pkg-1.0.0-1.rockspec", rockspec_content("up-pkg", "1.0.0-1"))

      upload_conn = fresh_conn(scope.user)

      upload_conn =
        post(upload_conn, ~p"/api/releases", %{
          "package" => "up-pkg",
          "version" => "1.0.0-1",
          "rockspec" => upload
        })

      assert %{"id" => release_id} = json_response(upload_conn, 201)["data"]

      assert Enum.any?(Luxpkgs.Audit.list_events(), fn event ->
               event.action == "release.published" and event.target_id == release_id and
                 event.metadata["version"] == "1.0.0-1"
             end)

      dl_conn = fresh_conn()
      dl_conn = get(dl_conn, ~p"/api/releases/#{release_id}")
      assert dl_conn.status == 200
    end

    test "download latest version", %{conn: conn, scope: scope} do
      post(conn, ~p"/api/packages",
        package: %{
          name: "dl-pkg",
          summary: "S",
          description: "D"
        }
      )

      package = Luxpkgs.Packages.get_package!("dl-pkg")
      release_fixture(scope, package, version: "1.0.0")
      release_fixture(scope, package, version: "2.0.0")

      dl_conn = fresh_conn()
      dl_conn = get(dl_conn, ~p"/api/download/dl-pkg")
      assert dl_conn.status == 200
    end

    test "download specific version", %{conn: conn, scope: scope} do
      post(conn, ~p"/api/packages",
        package: %{
          name: "vers-pkg",
          summary: "S",
          description: "D"
        }
      )

      package = Luxpkgs.Packages.get_package!("vers-pkg")
      release_fixture(scope, package, version: "1.0.0")
      release_fixture(scope, package, version: "2.0.0")

      dl_conn = fresh_conn()
      dl_conn = get(dl_conn, ~p"/api/download/vers-pkg/1.0.0")
      assert dl_conn.status == 200
    end

    test "non-rockspec file returns 400", %{conn: conn, user: user} do
      post(conn, ~p"/api/packages",
        package: %{
          name: "badfile-pkg",
          summary: "S",
          description: "D"
        }
      )

      upload = create_rockspec_upload("badfile.txt", "not a rockspec")

      upload_conn = fresh_conn(user)

      upload_conn =
        post(upload_conn, ~p"/api/releases", %{
          "package" => "badfile-pkg",
          "version" => "1.0.0-1",
          "rockspec" => upload
        })

      assert json_response(upload_conn, 400)
    end

    test "release for nonexistent package returns 404", %{conn: conn} do
      upload =
        create_rockspec_upload("ghost-1.0.0-1.rockspec", rockspec_content("ghost-pkg", "1.0.0-1"))

      conn =
        post(conn, ~p"/api/releases", %{
          "package" => "ghost-pkg",
          "version" => "1.0.0-1",
          "rockspec" => upload
        })

      assert json_response(conn, 404)
    end

    test "invalid rockspec content returns 422", %{conn: conn, scope: scope} do
      post(conn, ~p"/api/packages",
        package: %{
          name: "invalid-rs-pkg",
          summary: "S",
          description: "D"
        }
      )

      upload = create_rockspec_upload("invalid-rs-1.0.0-1.rockspec", "not valid")

      upload_conn = fresh_conn(scope.user)

      upload_conn =
        post(upload_conn, ~p"/api/releases", %{
          "package" => "invalid-rs-pkg",
          "version" => "1.0.0-1",
          "rockspec" => upload
        })

      assert json_response(upload_conn, 422)["errors"]
    end

    test "duplicate version returns 422", %{conn: conn, scope: scope} do
      post(conn, ~p"/api/packages",
        package: %{
          name: "dup-ver-pkg",
          summary: "S",
          description: "D"
        }
      )

      upload1 =
        create_rockspec_upload(
          "dup-ver-1.0.0-1.rockspec",
          rockspec_content("dup-ver-pkg", "1.0.0-1")
        )

      c1 = fresh_conn(scope.user)

      r1 =
        post(c1, ~p"/api/releases", %{
          "package" => "dup-ver-pkg",
          "version" => "1.0.0-1",
          "rockspec" => upload1
        })

      assert json_response(r1, 201)

      upload2 =
        create_rockspec_upload(
          "dup-ver-1.0.0-2.rockspec",
          rockspec_content("dup-ver-pkg", "1.0.0-1")
        )

      c2 = fresh_conn(scope.user)

      r2 =
        post(c2, ~p"/api/releases", %{
          "package" => "dup-ver-pkg",
          "version" => "1.0.0-1",
          "rockspec" => upload2
        })

      assert json_response(r2, 422)["errors"]
    end
  end

  describe "authentication and scope" do
    test "write-restricted scope cannot create packages" do
      user = Luxpkgs.AccountsFixtures.user_fixture()

      {:ok, jwt, _} =
        Luxpkgs.Guardian.encode_and_sign(user, %{
          "allowed_packages" => nil,
          "write_restriction" => true
        })

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{jwt}")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/packages", package: %{name: "nope", summary: "S", description: "D"})

      assert json_response(conn, 403)
    end

    test "package whitelist restricts to allowed packages only" do
      user = Luxpkgs.AccountsFixtures.user_fixture()

      {:ok, jwt, _} =
        Luxpkgs.Guardian.encode_and_sign(user, %{
          "allowed_packages" => ["allowed-pkg"],
          "write_restriction" => false
        })

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{jwt}")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/packages",
          package: %{name: "not-allowed", summary: "S", description: "D"}
        )

      assert json_response(conn, 403)
    end

    test "package whitelist allows whitelisted package" do
      user = Luxpkgs.AccountsFixtures.user_fixture()

      {:ok, jwt, _} =
        Luxpkgs.Guardian.encode_and_sign(user, %{
          "allowed_packages" => ["allowed-pkg"],
          "write_restriction" => false
        })

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{jwt}")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/packages",
          package: %{"name" => "allowed-pkg", "summary" => "S", "description" => "D"}
        )

      assert json_response(conn, 201)
    end

    test "revoked key cannot create packages", %{scope: scope} do
      jwt =
        case Luxpkgs.Guardian.encode_and_sign(scope.user, %{
               "allowed_packages" => nil,
               "write_restriction" => false
             }) do
          {:ok, jwt, _} -> jwt
        end

      Luxpkgs.RevokedKeys.create_revoked_key(scope, %{revoked_key: jwt})

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{jwt}")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/packages", package: %{name: "revoked", summary: "S", description: "D"})

      assert json_response(conn, 403)
    end

    test "revoke endpoint works for authenticated user", %{conn: conn} do
      conn = post(conn, ~p"/api/revoke")
      assert conn.status == 200
    end
  end

  describe "edge cases" do
    test "release of unowned package returns 403" do
      owner = Luxpkgs.AccountsFixtures.user_fixture()
      owner_scope = Luxpkgs.Accounts.Scope.for_user(owner)
      _package = package_fixture(owner_scope, %{name: "owner-pkg"})

      other_user = Luxpkgs.AccountsFixtures.user_fixture()

      upload =
        create_rockspec_upload(
          "owner-pkg-1.0.0-1.rockspec",
          rockspec_content("owner-pkg", "1.0.0-1")
        )

      conn = fresh_conn(other_user)

      conn =
        post(conn, ~p"/api/releases", %{
          "package" => "owner-pkg",
          "version" => "1.0.0-1",
          "rockspec" => upload
        })

      assert json_response(conn, 403)
    end

    test "download nonexistent version returns 404", %{scope: scope} do
      package = package_fixture(scope, %{name: "nover-pkg"})
      release_fixture(scope, package, version: "1.0.0")

      conn = fresh_conn()
      conn = get(conn, ~p"/api/download/nover-pkg/9.9.9")
      assert json_response(conn, 404)
    end
  end
end
