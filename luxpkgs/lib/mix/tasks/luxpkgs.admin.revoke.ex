defmodule Mix.Tasks.Luxpkgs.Admin.Revoke do
  use Mix.Task

  @shortdoc "Revokes admin or moderator access from a user"

  @moduledoc """
  Revokes admin or moderator access from a user.

      mix luxpkgs.admin.revoke --user-id 42

  The admin record is kept and marked inactive, so audit history and
  references remain valid. Revoking an already inactive admin is safe.
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

    case Luxpkgs.Admin.revoke_by_user_id(user_id) do
      {:ok, admin} ->
        Mix.shell().info(
          "Admin access for user #{admin.user_id} (#{admin.user.username}) is now revoked."
        )

      {:error, reason} ->
        Mix.raise(error_message(reason))
    end
  end

  defp error_message(:invalid_user_id),
    do: "--user-id must be a positive integer."

  defp error_message(:not_found),
    do: "No admin record exists for that user."

  defp error_message(reason),
    do: "Could not revoke admin access: #{inspect(reason)}"

  defp format_invalid(invalid) do
    Enum.map_join(invalid, ", ", fn {option, value} -> "#{option}=#{value}" end)
  end
end
