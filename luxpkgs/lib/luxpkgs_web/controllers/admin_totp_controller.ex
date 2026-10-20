defmodule LuxpkgsWeb.AdminTotpController do
  use LuxpkgsWeb, :controller

  alias Luxpkgs.Accounts
  alias Luxpkgs.Accounts.User
  alias Luxpkgs.Admin
  alias Luxpkgs.Audit
  alias LuxpkgsWeb.AdminAuth

  def new(conn, _params) do
    case admin_context(conn) do
      {:ok, _user, _admin} ->
        if AdminAuth.page_fresh?(get_session(conn, :admin_totp_verified_at)) do
          redirect(conn, to: ~p"/admin")
        else
          render(conn, :new,
            page_title: "Admin verification",
            current_scope: conn.assigns.current_scope
          )
        end

      {:error, reason} ->
        redirect_for_error(conn, reason)
    end
  end

  def create(conn, %{"code" => code}) when is_binary(code) do
    case admin_context(conn) do
      {:ok, user, admin} ->
        case Accounts.TOTP.verify(user, code) do
          :ok ->
            conn
            |> put_session(:admin_totp_verified_at, System.os_time(:second))
            |> record_verification(admin, user)
            |> put_flash(:info, "Admin access verified.")
            |> redirect(to: ~p"/admin")

          :error ->
            conn
            |> put_flash(:error, "Invalid verification code.")
            |> redirect(to: ~p"/admin/verify")
        end

      {:error, reason} ->
        redirect_for_error(conn, reason)
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Enter a verification code.")
    |> redirect(to: ~p"/admin/verify")
  end

  defp admin_context(conn) do
    case conn.assigns[:current_scope] do
      %{user: %User{} = user} ->
        case Admin.get_active_admin_for_user(user) do
          nil ->
            {:error, :not_admin}

          admin ->
            if User.has_totp?(user) do
              {:ok, user, admin}
            else
              {:error, :no_totp}
            end
        end

      _ ->
        {:error, :unauthenticated}
    end
  end

  defp redirect_for_error(conn, :unauthenticated) do
    conn
    |> put_flash(:error, "You must log in to access this page.")
    |> redirect(to: ~p"/login")
  end

  defp redirect_for_error(conn, :not_admin) do
    conn
    |> put_flash(:error, "Admin access required.")
    |> redirect(to: ~p"/")
  end

  defp redirect_for_error(conn, :no_totp) do
    conn
    |> put_flash(:error, "Set up two-factor authentication first.")
    |> redirect(to: ~p"/setup-totp")
  end

  defp record_verification(conn, admin, user) do
    _ =
      Audit.record(%{
        type: :auth,
        action: "admin.totp_verified",
        actor_admin_id: admin.id,
        actor_label: user.username,
        target_type: "admin",
        target_id: admin.id,
        target_label: user.username,
        metadata: %{"role" => to_string(admin.role)}
      })

    conn
  end
end
