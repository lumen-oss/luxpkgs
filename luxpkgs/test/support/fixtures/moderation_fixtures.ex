defmodule Luxpkgs.ModerationFixtures do
  def report_fixture(user, package, attrs \\ %{}) do
    attrs = Map.merge(%{reason: :spam, details: "Report details"}, attrs)

    case Luxpkgs.Moderation.create_report(user, package, attrs) do
      {:ok, report} -> report
      {:error, reason} -> raise "could not create report fixture: #{inspect(reason)}"
    end
  end
end
