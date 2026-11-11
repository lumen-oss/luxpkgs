defmodule LuxpkgsRockspecVerifierWeb.VerifyControllerTest do
  # The large-rockspec cases are CPU heavy; keep them out of the async pool.
  use LuxpkgsRockspecVerifierWeb.ConnCase, async: false

  @max_rockspec_bytes 48 * 1024
  @kong_fixture Path.expand("../../fixtures/kong-3.9.4-0.rockspec", __DIR__)

  defp kong_rockspec, do: File.read!(@kong_fixture)

  defp json_post(conn, path, params) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, params)
  end

  test "accepts a real rockspec larger than the old 2.5 KB limit", %{conn: conn} do
    rockspec = kong_rockspec()
    assert byte_size(rockspec) > 32_768
    assert byte_size(rockspec) < @max_rockspec_bytes

    conn =
      json_post(conn, ~p"/verify", %{
        rockspec: rockspec,
        package: "kong",
        version: "3.9.4-0"
      })

    assert %{"message" => "Rockspec is valid", "metadata" => metadata} =
             json_response(conn, 200)

    assert metadata["summary"] =~ "Kong is a scalable"
    assert metadata["homepage"] == "https://konghq.com"
    assert metadata["license"] == "Apache 2.0"
    assert metadata["platforms"] == ["linux", "macosx"]
    assert metadata["build_type"] == "builtin"
    assert "inspect == 3.1.3" in metadata["dependencies"]
  end

  test "parses a real rockspec larger than the old 2.5 KB limit", %{conn: conn} do
    conn = json_post(conn, ~p"/parse", %{rockspec: kong_rockspec()})

    assert %{"package" => "kong", "version" => "3.9.4-0", "metadata" => metadata} =
             json_response(conn, 200)

    assert metadata["license"] == "Apache 2.0"
  end

  test "rejects a rockspec larger than 48 KB", %{conn: conn} do
    rockspec = String.duplicate("a", @max_rockspec_bytes + 1)

    conn =
      json_post(conn, ~p"/verify", %{
        rockspec: rockspec,
        package: "kong",
        version: "3.9.4-0"
      })

    assert json_response(conn, 400) == %{"error" => "Invalid parameters"}
  end
end
