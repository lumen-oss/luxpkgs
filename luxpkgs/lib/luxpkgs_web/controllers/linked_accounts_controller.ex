defmodule LuxpkgsWeb.LinkedAccountsController do
  use LuxpkgsWeb, :controller

  alias Luxpkgs.AtpOauth

  plug :require_sudo_mode

  def create(conn, %{"provider" => "github"}) do
    conn
    |> put_link_intent()
    |> redirect(to: ~p"/auth/github")
  end

  def create(conn, %{"provider" => "atproto"} = params) do
    cond do
      not AtpOauth.configured?() ->
        conn
        |> put_flash(:error, "AT Protocol login is not available right now.")
        |> redirect(to: ~p"/settings")

      true ->
        case AtpOauth.authorize(params["handle"]) do
          {:ok, url} ->
            conn
            |> put_link_intent()
            |> redirect(external: url)

          {:error, _reason} ->
            conn
            |> put_flash(:error, "Could not sign in with that handle.")
            |> redirect(to: ~p"/settings")
        end
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Unsupported provider.")
    |> redirect(to: ~p"/settings")
  end

  def delete(conn, %{"provider" => provider}) do
    case Luxpkgs.Accounts.unlink_identity(conn.assigns.current_scope.user, provider) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Account unlinked.")
        |> redirect(to: ~p"/settings")

      {:error, :last_identity} ->
        conn
        |> put_flash(:error, "You must keep at least one linked account.")
        |> redirect(to: ~p"/settings")

      {:error, :not_linked} ->
        conn
        |> put_flash(:error, "That account is no longer linked.")
        |> redirect(to: ~p"/settings")

      {:error, :unlink_failed} ->
        conn
        |> put_flash(:error, "Could not unlink that account. Please try again.")
        |> redirect(to: ~p"/settings")
    end
  end

  defp put_link_intent(conn) do
    conn
    |> put_session(:oauth_link_user_id, conn.assigns.current_scope.user.id)
    |> put_session(:oauth_link_at, System.os_time(:second))
  end

  defp require_sudo_mode(conn, _opts) do
    if Luxpkgs.Accounts.sudo_mode?(conn.assigns.current_scope.user, -10) do
      conn
    else
      conn
      |> put_flash(:error, "Please re-authenticate to link an account.")
      |> redirect(to: ~p"/settings")
      |> halt()
    end
  end
end
