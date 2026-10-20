defmodule Mix.Tasks.Luxpkgs.Admin.List do
  use Mix.Task

  @shortdoc "Lists admin and moderator accounts"

  @moduledoc """
  Lists admin and moderator accounts with their linked user IDs.

      mix luxpkgs.admin.list
  """

  @impl Mix.Task
  def run(args) do
    if args != [] do
      Mix.raise("Unexpected arguments: #{Enum.join(args, " ")}")
    end

    Mix.Task.run("app.start")

    case Luxpkgs.Admin.list() do
      [] ->
        Mix.shell().info("No admins.")

      admins ->
        print(admins)
    end
  end

  defp print(admins) do
    rows = [header() | Enum.map(admins, &row/1)]
    widths = column_widths(rows)

    Enum.each(rows, fn row ->
      Mix.shell().info(format_row(row, widths))
    end)
  end

  defp header, do: ["user_id", "role", "status", "username"]

  defp row(admin) do
    [
      Integer.to_string(admin.user_id),
      Atom.to_string(admin.role),
      if(admin.active, do: "active", else: "revoked"),
      admin.user.username
    ]
  end

  defp column_widths(rows) do
    rows
    |> Enum.zip()
    |> Enum.map(fn column ->
      column
      |> Tuple.to_list()
      |> Enum.map(&String.length/1)
      |> Enum.max()
    end)
  end

  defp format_row(row, widths) do
    row
    |> Enum.zip(widths)
    |> Enum.map_join("  ", fn {value, width} -> String.pad_trailing(value, width) end)
    |> String.trim_trailing()
  end
end
