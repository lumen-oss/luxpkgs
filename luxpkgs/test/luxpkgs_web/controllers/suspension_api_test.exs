defmodule LuxpkgsWeb.SuspensionApiTest do
  use LuxpkgsWeb.ConnCase

  import Luxpkgs.AccountsFixtures
  import Luxpkgs.AdminFixtures

  alias Luxpkgs.Accounts

  describe "suspended API access" do
    test "rejects a bearer token belonging to a suspended user", %{conn: conn} do
      user = user_fixture()
      actor = admin_fixture(%{role: :admin})

      {:ok, token, _claims} =
        Luxpkgs.Guardian.encode_and_sign(user, %{
          "allowed_packages" => nil,
          "write_restriction" => false
        })

      {:ok, _user, _tokens} = Accounts.suspend_user(actor, user, "Spam")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/packages", %{
          package: %{"name" => "suspended", "summary" => "S", "description" => "D"}
        })

      assert json_response(conn, 401)
    end

    test "does not build a scope from a suspended user's claims" do
      user = user_fixture()
      actor = admin_fixture(%{role: :admin})
      {:ok, _user, _tokens} = Accounts.suspend_user(actor, user, "Spam")

      claims = %{
        "sub" => to_string(user.id),
        "allowed_packages" => nil,
        "write_restriction" => false
      }

      assert {:error, :user_suspended} = Luxpkgs.Guardian.resource_from_claims(claims)
    end
  end
end
