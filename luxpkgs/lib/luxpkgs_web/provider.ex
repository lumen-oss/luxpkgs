defmodule LuxpkgsWeb.Provider do
  @moduledoc "Display name and icon for an account provider."

  def label(provider), do: provider |> to_string() |> label_for()

  def icon(provider), do: provider |> to_string() |> icon_for()

  defp label_for("github"), do: "GitHub"
  defp label_for("atproto"), do: "AT Protocol"
  defp label_for(provider), do: String.capitalize(provider)

  defp icon_for("github"), do: :brand_github
  defp icon_for("atproto"), do: :tangled
  defp icon_for(_provider), do: :code
end
