defmodule LuxpkgsWeb.UserOauth do
  use LuxpkgsWeb, :controller

  plug(Ueberauth)

  require Logger

  def callback(%{assigns: %{ueberauth_failure: %Ueberauth.Failure{}}} = conn, _params) do
    handle_failure(conn)
  end

  def callback(%{assigns: %{ueberauth_auth: %Ueberauth.Auth{} = auth}} = conn, _params) do
    handle_auth(conn, auth)
  end

  def handle_failure(conn, message \\ "Failed to authenticate") do
    conn
    |> clear_link_intent()
    |> put_flash(:error, message)
    |> redirect(to: ~p"/")
  end

  def handle_auth(conn, %Ueberauth.Auth{} = auth) do
    {intent_user, conn} = take_link_intent(conn)

    case intent_user do
      %Luxpkgs.Accounts.User{} = user -> handle_link(conn, user, auth)
      nil -> handle_login(conn, auth)
    end
  end

  defp handle_login(conn, %Ueberauth.Auth{} = auth) do
    case Luxpkgs.Accounts.get_user_by_auth(auth) do
      %Luxpkgs.Accounts.User{} = user ->
        Luxpkgs.Accounts.sync_profile(user, auth)

        cond do
          Luxpkgs.Accounts.User.suspended?(user) ->
            conn
            |> put_flash(:error, "Account suspended.")
            |> redirect(to: ~p"/")

          Luxpkgs.Accounts.User.has_totp?(user) ->
            conn
            |> LuxpkgsWeb.UserAuth.log_in_user(user)

          true ->
            conn
            |> put_session(:pending_totp_user_id, user.id)
            |> redirect(to: ~p"/setup-totp")
        end

      nil when is_nil(auth.info.email) ->
        auth_stripped = %{
          provider: auth.provider,
          uid: auth.uid,
          pds_endpoint: pds_endpoint(auth),
          info: %{
            nickname: auth.info.nickname,
            name: auth.info.name,
            email: auth.info.email,
            image: auth.info.image
          }
        }

        conn
        |> put_session(:oauth_signup_token, auth_stripped)
        |> redirect(to: ~p"/provide-email")

      nil ->
        # User doesn't exist but has email from OAuth, create the user
        case Luxpkgs.Accounts.register_user(auth) do
          {:ok, user} ->
            if Luxpkgs.Accounts.User.has_totp?(user) do
              conn
              |> put_flash(:info, "Account created successfully.")
              |> LuxpkgsWeb.UserAuth.log_in_user(user)
            else
              conn
              |> put_session(:pending_totp_user_id, user.id)
              |> redirect(to: ~p"/setup-totp")
            end

          {:error, changeset} ->
            Logger.error("Failed to create user from OAuth, see changeset:")
            Logger.error(inspect(changeset))

            conn
            |> put_flash(:error, "Authentication succeeded, but failed to create user.")
            |> redirect(to: ~p"/")
        end
    end
  end

  defp pds_endpoint(%Ueberauth.Auth{extra: %Ueberauth.Auth.Extra{raw_info: raw_info}})
       when is_map(raw_info) do
    raw_info[:pds_endpoint]
  end

  defp pds_endpoint(_auth), do: nil

  @link_intent_ttl 600

  defp take_link_intent(conn) do
    user_id = get_session(conn, :oauth_link_user_id)
    at = get_session(conn, :oauth_link_at)
    conn = clear_link_intent(conn)

    user =
      with true <- is_integer(user_id),
           %Luxpkgs.Accounts.User{} = user <- Luxpkgs.Accounts.get_user(user_id),
           true <- is_integer(at),
           true <- System.os_time(:second) - at <= @link_intent_ttl do
        user
      else
        _ -> nil
      end

    {user, conn}
  end

  defp clear_link_intent(conn) do
    conn
    |> delete_session(:oauth_link_user_id)
    |> delete_session(:oauth_link_at)
  end

  # A link intent only adds an identity to the session user; it never logs in.
  defp handle_link(conn, %Luxpkgs.Accounts.User{} = user, %Ueberauth.Auth{} = auth) do
    if Luxpkgs.Accounts.User.suspended?(user) do
      conn
      |> put_flash(:error, "Account suspended.")
      |> redirect(to: ~p"/")
    else
      case Luxpkgs.Accounts.link_identity(user, auth) do
        {:ok, :linked} ->
          conn
          |> put_flash(:info, "Account linked.")
          |> redirect(to: ~p"/settings")

        {:ok, :already_linked} ->
          conn
          |> put_flash(:info, "That account is already linked.")
          |> redirect(to: ~p"/settings")

        {:error, :taken} ->
          conn
          |> put_flash(:error, "That account is already linked to another user.")
          |> redirect(to: ~p"/settings")

        {:error, :different_identity} ->
          conn
          |> put_flash(
            :error,
            "You already linked a different #{LuxpkgsWeb.Provider.label(auth.provider)} account."
          )
          |> redirect(to: ~p"/settings")

        {:error, changeset} ->
          Logger.error(
            "Could not link an identity for user #{user.id}: #{inspect(changeset.errors)}"
          )

          conn
          |> put_flash(:error, "Could not link that account. Please try again.")
          |> redirect(to: ~p"/settings")
      end
    end
  end

  def complete_signup(conn, %{"user" => %{"email" => email}}) do
    auth = get_session(conn, :oauth_signup_token)

    cond do
      is_nil(auth) ->
        conn
        |> put_flash(:error, "Your signup session expired. Please try authenticating again.")
        |> redirect(to: ~p"/login")

      # The email has already been set and the user has navigated to the page in an unnatural way
      not is_nil(auth.info.email) ->
        conn
        |> put_flash(
          :error,
          "Unable to modify account with public email. Please try authenticating again."
        )
        |> redirect(to: ~p"/login")

      true ->
        ueberauth = %Ueberauth.Auth{
          provider: auth.provider,
          uid: auth[:uid],
          extra: %Ueberauth.Auth.Extra{raw_info: %{pds_endpoint: auth[:pds_endpoint]}},
          info: %Ueberauth.Auth.Info{
            nickname: auth.info.nickname,
            name: auth.info.name,
            email: email,
            image: auth.info.image
          }
        }

        case Luxpkgs.Accounts.register_user(ueberauth) do
          {:ok, user} ->
            if Luxpkgs.Accounts.User.has_totp?(user) do
              conn
              |> put_flash(:info, "Account created successfully.")
              |> LuxpkgsWeb.UserAuth.log_in_user(user)
            else
              conn
              |> put_session(:pending_totp_user_id, user.id)
              |> redirect(to: ~p"/setup-totp")
            end

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Failed to create account. Please check your email.")
            |> redirect(to: ~p"/provide-email")
        end
    end
  end

  def complete_signup(conn, _params) do
    conn
    |> put_flash(:error, "Missing required parameters. Please try authenticating again.")
    |> redirect(to: ~p"/login")
  end

  def complete_totp_setup(conn, %{"code" => code}) do
    user = totp_setup_user(conn)

    with %Luxpkgs.Accounts.User{} = user <- user,
         false <- Luxpkgs.Accounts.User.has_totp?(user),
         {:ok, secret_b32} when is_binary(secret_b32) <- Cachex.get(:totp_setup, user.id),
         {:ok, secret} <- Base.decode32(secret_b32, padding: false),
         true <- Luxpkgs.Accounts.TOTP.valid?(secret, code),
         :ok <- Luxpkgs.Accounts.TOTP.enable(user, secret) do
      Cachex.del(:totp_setup, user.id)
      codes = Luxpkgs.Accounts.TOTP.generate_backup_codes(user)
      Cachex.put(:totp_backup_codes, user.id, codes, ttl: :timer.hours(1))

      conn
      |> put_session(:user_return_to, ~p"/settings")
      |> LuxpkgsWeb.UserAuth.log_in_user(user)
    else
      _ -> reject_totp_setup(conn, user)
    end
  end

  def complete_totp_setup(conn, _params) do
    conn
    |> put_flash(:error, "Missing verification code.")
    |> redirect(to: ~p"/setup-totp")
  end

  defp totp_setup_user(conn) do
    case get_session(conn, :pending_totp_user_id) do
      nil ->
        case get_session(conn, :user_token) do
          nil ->
            nil

          token ->
            case Luxpkgs.Accounts.get_user_by_session_token(token) do
              {user, _token_inserted_at} -> user
              _ -> nil
            end
        end

      user_id ->
        Luxpkgs.Accounts.get_user(user_id)
    end
  end

  defp reject_totp_setup(conn, user) do
    if user do
      Logger.warning("Rejected TOTP setup for user #{user.id} from #{inspect(conn.remote_ip)}")
    end

    to =
      if user && Luxpkgs.Accounts.User.has_totp?(user) do
        ~p"/settings"
      else
        ~p"/setup-totp"
      end

    conn
    |> put_flash(:error, "Invalid verification code. Please try again.")
    |> redirect(to: to)
  end
end
