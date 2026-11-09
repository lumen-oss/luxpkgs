defmodule LuxpkgsWeb.PageControllerTest do
  use LuxpkgsWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Luxpkgs"
    assert html_response(conn, 200) =~ ~s(id="theme-dropdown")
  end
end
