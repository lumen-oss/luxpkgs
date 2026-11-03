defmodule LuxpkgsWeb.ReleaseControllerTest do
  use LuxpkgsWeb.ConnCase

  import Luxpkgs.PackagesFixtures

  setup %{conn: conn} do
    user = Luxpkgs.AccountsFixtures.user_fixture()
    scope = Luxpkgs.Accounts.Scope.for_user(user)
    conn = conn |> authenticate_api_user(user) |> put_req_header("accept", "application/json")
    {:ok, conn: conn, user: user, scope: scope}
  end

  describe "show release" do
    test "returns the release as file download", %{conn: conn, scope: scope} do
      release = release_fixture(scope)
      conn = get(conn, ~p"/api/releases/#{release.id}")
      assert conn.status == 200
    end

    test "returns 404 for unknown release", %{conn: conn} do
      conn = get(conn, ~p"/api/releases/999999")
      assert json_response(conn, 404)
    end

    test "returns 404 for a release of a non-active package", %{conn: conn, scope: scope} do
      release = release_fixture(scope)

      Luxpkgs.Packages.Package
      |> Luxpkgs.Repo.get!(release.package_id)
      |> Ecto.Changeset.change(status: :hidden)
      |> Luxpkgs.Repo.update!()

      conn = get(conn, ~p"/api/releases/#{release.id}")

      assert json_response(conn, 404)
      assert Luxpkgs.Repo.get!(Luxpkgs.Packages.Release, release.id).download_count == 0
    end
  end
end
