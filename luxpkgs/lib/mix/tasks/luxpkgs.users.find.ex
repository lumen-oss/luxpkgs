defmodule Mix.Tasks.Luxpkgs.Users.Find do
  use Mix.Task

  alias Luxpkgs.Accounts
  alias Luxpkgs.Accounts.User
  alias Luxpkgs.Admin
  alias Luxpkgs.Admin.Admin, as: AdminRow

  @shortdoc "Finds a user and prints their internal ID"

  @moduledoc """
  Finds a user by id, email, or username and prints the internal ID used by
  the other admin tasks.

      mix luxpkgs.users.find --id 42
      mix luxpkgs.users.find --email alice@example.com
      mix luxpkgs.users.find --username alice

  Provide exactly one of the three options.
  """

  @impl Mix.Task
  def run(args) do
    {opts, argv, invalid} =
      OptionParser.parse(args, strict: [id: :integer, email: :string, username: :string])

    if argv != [] do
      Mix.raise("Unexpected arguments: #{Enum.join(argv, " ")}")
    end

    if invalid != [] do
      Mix.raise("Invalid options: #{format_invalid(invalid)}")
    end

    selectors = Keyword.take(opts, [:id, :email, :username])

    Mix.Task.run("app.start")

    selectors
    |> find_user()
    |> print()
  end

  defp find_user(id: id) when is_integer(id) and id > 0 do
    Accounts.get_user(id) || Mix.raise("No user found with ID #{id}.")
  end

  defp find_user(id: _id), do: Mix.raise("--id must be a positive integer.")

  defp find_user(email: email) when is_binary(email) do
    Accounts.get_user_by_email(email) || Mix.raise("No user found with email #{email}.")
  end

  defp find_user(username: username) when is_binary(username) do
    Accounts.get_user_by_username(username) ||
      Mix.raise("No user found with username #{username}.")
  end

  defp find_user([]), do: Mix.raise("Provide one of --id, --email, or --username.")

  defp find_user(_selectors),
    do: Mix.raise("Provide only one of --id, --email, or --username.")

  defp print(user) do
    rows = [
      {"id", Integer.to_string(user.id)},
      {"username", user.username || "-"},
      {"email", user.email || "-"},
      {"provider", user.provider || "-"},
      {"status", status(user)},
      {"admin", admin(user)},
      {"totp", if(User.has_totp?(user), do: "enabled", else: "disabled")}
    ]

    width = rows |> Enum.map(fn {label, _value} -> String.length(label) end) |> Enum.max()

    Enum.each(rows, fn {label, value} ->
      Mix.shell().info(String.pad_trailing(label <> ":", width + 1) <> " " <> value)
    end)
  end

  defp status(%User{suspended_at: nil}), do: "active"
  defp status(%User{suspension_reason: nil}), do: "suspended"
  defp status(%User{suspension_reason: reason}), do: "suspended (#{reason})"

  defp admin(%User{} = user) do
    case Admin.get_admin_for_user(user) do
      nil -> "none"
      %AdminRow{role: role, active: true} -> "#{role} (active)"
      %AdminRow{role: role} -> "#{role} (revoked)"
    end
  end

  defp format_invalid(invalid) do
    Enum.map_join(invalid, ", ", fn {option, value} -> "#{option}=#{value}" end)
  end
end
