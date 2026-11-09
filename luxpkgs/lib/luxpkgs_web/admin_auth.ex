defmodule LuxpkgsWeb.AdminAuth do
  use LuxpkgsWeb, :verified_routes

  alias Luxpkgs.Accounts.User
  alias Luxpkgs.Admin

  @page_freshness_seconds 30 * 60
  @destructive_freshness_seconds 10 * 60

  def on_mount(:require_admin, _params, session, socket) do
    user = current_user(socket)
    admin = user && Admin.get_active_admin_for_user(user)
    verified_at = session["admin_totp_verified_at"]

    cond do
      is_nil(user) ->
        halt(socket, "You must log in to access this page.", ~p"/login")

      is_nil(admin) ->
        halt(socket, "Admin access required.", ~p"/")

      not User.has_totp?(user) ->
        halt(socket, "Set up two-factor authentication first.", ~p"/setup-totp")

      not page_fresh?(verified_at) ->
        halt(socket, "Verify your second factor to continue.", ~p"/admin/verify")

      true ->
        {:cont,
         Phoenix.Component.assign(socket,
           current_admin: admin,
           admin_totp_verified_at: verified_at
         )}
    end
  end

  def page_fresh?(verified_at), do: fresh?(verified_at, @page_freshness_seconds)

  def destructive_fresh?(%{assigns: %{admin_totp_verified_at: verified_at}}),
    do: fresh?(verified_at, @destructive_freshness_seconds)

  def destructive_fresh?(_socket), do: false

  defp current_user(%{assigns: %{current_scope: %{user: %User{} = user}}}), do: user
  defp current_user(_socket), do: nil

  defp fresh?(verified_at, max_age) when is_integer(verified_at) do
    age = System.os_time(:second) - verified_at
    age >= 0 and age <= max_age
  end

  defp fresh?(_verified_at, _max_age), do: false

  defp halt(socket, message, path) do
    {:halt,
     socket
     |> Phoenix.LiveView.put_flash(:error, message)
     |> Phoenix.LiveView.redirect(to: path)}
  end
end
