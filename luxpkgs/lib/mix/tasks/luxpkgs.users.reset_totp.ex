defmodule Mix.Tasks.Luxpkgs.Users.ResetTotp do
  use Mix.Task

  @shortdoc "Clears a user's TOTP and revokes their sessions"

  @moduledoc """
  Clears a user's two-factor authentication and revokes all session tokens.

      mix luxpkgs.users.reset_totp --user-id 42

  Use this only when a user has lost both their authenticator and their backup
  codes. The user must set up TOTP again.
  """

  @impl Mix.Task
  def run(args) do
    {opts, argv, invalid} = OptionParser.parse(args, strict: [user_id: :integer])

    if argv != [] do
      Mix.raise("Unexpected arguments: #{Enum.join(argv, " ")}")
    end

    if invalid != [] do
      Mix.raise("Invalid options: #{format_invalid(invalid)}")
    end

    user_id = Keyword.get(opts, :user_id) || Mix.raise("Missing --user-id")

    Mix.Task.run("app.start")

    with {:ok, user} <- fetch_user(user_id),
         {:ok, tokens} <- Luxpkgs.Accounts.reset_totp(user) do
      LuxpkgsWeb.UserAuth.disconnect_sessions(tokens)

      Mix.shell().info(
        "TOTP reset for user #{user.id} (#{user.username || user.email}); " <>
          "#{length(tokens)} session(s) revoked."
      )
    else
      {:error, reason} -> Mix.raise(error_message(reason))
    end
  end

  defp fetch_user(id) when is_integer(id) and id > 0 do
    case Luxpkgs.Accounts.get_user(id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp fetch_user(_id), do: {:error, :invalid_user_id}

  defp error_message(:invalid_user_id),
    do: "--user-id must be a positive integer."

  defp error_message(:user_not_found),
    do: "No user exists with that ID."

  defp error_message(reason),
    do: "Could not reset TOTP: #{inspect(reason)}"

  defp format_invalid(invalid) do
    Enum.map_join(invalid, ", ", fn {option, value} -> "#{option}=#{value}" end)
  end
end
