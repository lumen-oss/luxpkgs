defmodule LuxpkgsWeb.AtpOauthController do
  use LuxpkgsWeb, :controller

  alias Luxpkgs.AtpOauth
  alias LuxpkgsWeb.UserOauth

  def client_metadata(conn, _params) do
    if AtpOauth.configured?() do
      json(conn, AtpOauth.client_metadata())
    else
      send_resp(conn, :not_found, "")
    end
  end

  def request(conn, %{"handle" => handle}) do
    if AtpOauth.configured?() do
      case AtpOauth.authorize(handle) do
        {:ok, url} -> redirect(conn, external: url)
        {:error, _reason} -> UserOauth.handle_failure(conn, "Could not sign in with that handle.")
      end
    else
      UserOauth.handle_failure(conn, "AT Protocol login is not available right now.")
    end
  end

  def request(conn, _params) do
    UserOauth.handle_failure(conn, "Enter your AT Protocol handle.")
  end

  def callback(conn, params) do
    case AtpOauth.callback(params) do
      {:ok, auth} -> UserOauth.handle_auth(conn, auth)
      {:error, _reason} -> UserOauth.handle_failure(conn)
    end
  end
end
