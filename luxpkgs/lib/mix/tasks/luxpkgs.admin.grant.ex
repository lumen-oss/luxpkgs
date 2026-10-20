defmodule Mix.Tasks.Luxpkgs.Admin.Grant do
  use Mix.Task

  @shortdoc "Grants admin or moderator access to a user"

  @moduledoc """
  Grants admin or moderator access to an existing user.

      mix luxpkgs.admin.grant --user-id 42 --role admin
      mix luxpkgs.admin.grant --user-id 42 --role moderator

  The user must already exist. This task never creates users or admin
  accounts.
  """

  @impl Mix.Task
  def run(args) do
    {opts, argv, invalid} =
      OptionParser.parse(args, strict: [user_id: :integer, role: :string])

    if argv != [] do
      Mix.raise("Unexpected arguments: #{Enum.join(argv, " ")}")
    end

    if invalid != [] do
      Mix.raise("Invalid options: #{format_invalid(invalid)}")
    end

    user_id = Keyword.get(opts, :user_id) || Mix.raise("Missing --user-id")
    role = Keyword.get(opts, :role) || Mix.raise("Missing --role")

    Mix.Task.run("app.start")

    case Luxpkgs.Admin.grant_by_user_id(user_id, role) do
      {:ok, admin} ->
        Mix.shell().info(
          "User #{admin.user_id} (#{admin.user.username}) now has the #{admin.role} role."
        )

      {:error, reason} ->
        Mix.raise(error_message(reason))
    end
  end

  defp error_message(:invalid_user_id),
    do: "--user-id must be a positive integer."

  defp error_message(:invalid_role),
    do: "--role must be admin or moderator."

  defp error_message(:user_not_found),
    do: "No user exists with that ID."

  defp error_message(:deleted_user),
    do: "The deleted user sentinel cannot be an admin."

  defp error_message(reason),
    do: "Could not grant admin access: #{inspect(reason)}"

  defp format_invalid(invalid) do
    Enum.map_join(invalid, ", ", fn {option, value} -> "#{option}=#{value}" end)
  end
end
