defmodule LuxpkgsWeb.AtpOauthControllerTest do
  use LuxpkgsWeb.ConnCase, async: true

  setup %{conn: conn} do
    {:ok, conn: init_test_session(conn, %{})}
  end

  test "serves the client metadata document", %{conn: conn} do
    conn = get(conn, "/oauth-client-metadata.json")

    assert %{"scope" => "atproto"} = json_response(conn, 200)
  end

  test "rejects an empty handle", %{conn: conn} do
    conn =
      conn
      |> fetch_flash()
      |> LuxpkgsWeb.AtpOauthController.request(%{"handle" => "  "})

    assert redirected_to(conn) == ~p"/"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Could not sign in with that handle."
  end
end
