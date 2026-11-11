defmodule LuxpkgsWeb.PackageLive.Show do
  alias Luxpkgs.Accounts.User
  alias Luxpkgs.Moderation
  alias Luxpkgs.Packages
  alias LuxpkgsWeb.RateLimit
  use LuxpkgsWeb, :live_view

  import LuxpkgsWeb.Components.NotFound
  import LuxpkgsWeb.Markdown, only: [markdown: 1]

  def mount(%{"name" => name}, _session, socket) do
    case Packages.get_package_any(name) do
      nil ->
        {:ok,
         socket
         |> assign(:not_found, true)
         |> assign(:page_title, "Package not found")}

      package ->
        owner? = owner?(socket, package)

        if package.status == :active or owner? do
          {:ok,
           socket
           |> assign(:not_found, false)
           |> assign(:owner, owner?)
           |> assign(:package, Luxpkgs.Repo.preload(package, :user))
           |> assign(:metadata, latest_metadata(package))
           |> assign(:report_state, report_state(socket, package, owner?))
           |> assign(:page_title, package.name)}
        else
          {:ok,
           socket
           |> assign(:not_found, true)
           |> assign(:page_title, "Package not found")}
        end
    end
  end

  def handle_event("report_package", params, socket) do
    package = Packages.get_package_any(socket.assigns.package.name)
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    cond do
      is_nil(package) or package.status != :active ->
        {:noreply, put_flash(socket, :error, "This package is not available for reports.")}

      is_nil(user) ->
        {:noreply, put_flash(socket, :error, "Sign in to report this package.")}

      socket.assigns.owner ->
        {:noreply, put_flash(socket, :error, "You cannot report your own package.")}

      not User.has_totp?(user) ->
        {:noreply,
         put_flash(socket, :error, "Enable two-factor authentication to report packages.")}

      true ->
        submit_report(socket, user, package, params)
    end
  end

  def handle_event("copy_command", _params, socket) do
    {:noreply, put_flash(socket, :info, "Command copied to clipboard!")}
  end

  def handle_event("yank_release", %{"id" => id}, socket) do
    set_release_yanked(socket, id, :yank)
  end

  def handle_event("unyank_release", %{"id" => id}, socket) do
    set_release_yanked(socket, id, :unyank)
  end

  defp set_release_yanked(socket, id, action) do
    package = socket.assigns.package

    with true <- socket.assigns[:owner] || false,
         %Luxpkgs.Packages.Release{} = release <- Packages.get_release(id),
         true <- release.package_id == package.id,
         {:ok, _release} <- apply_release_action(action, socket, release) do
      package = Packages.get_package_any(package.name) |> Luxpkgs.Repo.preload(:user)

      {:noreply,
       socket
       |> assign(:package, package)
       |> assign(:metadata, latest_metadata(package))
       |> put_flash(:info, if(action == :yank, do: "Release yanked.", else: "Release unyanked."))}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Could not update release.")}
    end
  end

  defp apply_release_action(:yank, socket, release) do
    Packages.yank_release(socket.assigns.current_scope, release)
  end

  defp apply_release_action(:unyank, socket, release) do
    Packages.unyank_release(socket.assigns.current_scope, release)
  end

  defp submit_report(socket, user, package, params) do
    case RateLimit.hit(:report, "user:report:#{user.id}") do
      {:deny, _retry_after} ->
        {:noreply, put_flash(socket, :error, "Too many reports. Try again later.")}

      {:allow, _count} ->
        case Moderation.create_report(user, package, params) do
          {:ok, _report} ->
            {:noreply,
             socket
             |> push_event("close_dialog", %{id: "report_package_modal"})
             |> assign(:report_state, :reported)
             |> put_flash(:info, "Report submitted. A moderator will review it.")}

          {:error, :already_open} ->
            {:noreply,
             socket
             |> push_event("close_dialog", %{id: "report_package_modal"})
             |> assign(:report_state, :reported)
             |> put_flash(:error, "You already have an open report for this package.")}

          {:error, %Ecto.Changeset{}} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Could not submit report. Choose a reason and keep details under 2,000 characters."
             )}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not submit report.")}
        end
    end
  end

  defp report_state(socket, package, owner?) do
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    cond do
      package.status != :active or owner? -> :hidden
      is_nil(user) -> :anonymous
      not User.has_totp?(user) -> :totp
      Moderation.open_report?(user, package) -> :reported
      true -> :form
    end
  end

  defp owner?(socket, package) do
    case socket.assigns[:current_scope] do
      %{user: %{id: id}} -> id == package.user_id
      _ -> false
    end
  end

  def handle_params(%{"name" => name}, _url, socket) do
    {:noreply, assign(socket, :package_name, name)}
  end

  defp format_date(date) do
    case date do
      %DateTime{} -> Calendar.strftime(date, "%B %d, %Y")
      %NaiveDateTime{} -> Calendar.strftime(date, "%B %d, %Y")
      _ -> "Unknown"
    end
  end

  defp latest_version(package) do
    case Packages.latest_release(package) do
      nil -> "-"
      release -> "v#{release.version}"
    end
  end

  defp latest_release(package), do: Packages.latest_release(package)

  defp description_for(package, metadata) do
    [package.description, metadata["detailed"]]
    |> Enum.find(&(is_binary(&1) and String.valid?(&1) and String.trim(&1) != ""))
  end

  defp latest_metadata(package) do
    case latest_release(package) do
      nil -> %{}
      release -> release.metadata || %{}
    end
  end

  defp lua_requirement(metadata) do
    case metadata["lua"] do
      lua when is_binary(lua) ->
        lua

      _ ->
        metadata
        |> Map.get("dependencies", [])
        |> List.wrap()
        |> Enum.find(&(is_binary(&1) and String.starts_with?(&1, "lua ")))
    end
  end

  @platform_labels %{
    "linux" => "Linux",
    "macosx" => "macOS",
    "windows" => "Windows",
    "unix" => "Unix"
  }

  defp platform_label(platform), do: Map.get(@platform_labels, platform, platform)

  defp build_label("builtin"), do: nil
  defp build_label(build) when is_binary(build), do: build
  defp build_label(_build), do: nil

  defp safe_url(url) when is_binary(url) do
    if String.valid?(url) do
      case URI.new(url) do
        {:ok, %URI{scheme: scheme, host: host}}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          url

        _ ->
          nil
      end
    end
  end

  defp safe_url(_url), do: nil

  @max_labels 6
  @max_label_length 24

  defp labels(metadata) do
    metadata
    |> Map.get("labels", [])
    |> List.wrap()
    |> Enum.filter(&(is_binary(&1) and String.valid?(&1)))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.take(@max_labels)
    |> Enum.map(&truncate_label/1)
  end

  defp truncate_label(label) do
    if String.length(label) > @max_label_length do
      String.slice(label, 0, @max_label_length - 3) <> "..."
    else
      label
    end
  end

  @max_dependencies 20
  @max_external_dependencies 10

  defp runtime_dependencies(metadata) do
    dependencies =
      metadata
      |> Map.get("dependencies", [])
      |> List.wrap()
      |> Enum.filter(&(is_binary(&1) and String.valid?(&1)))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.reject(&String.starts_with?(&1, "lua "))
      |> Enum.uniq()

    {Enum.take(dependencies, @max_dependencies), max(length(dependencies) - @max_dependencies, 0)}
  end

  defp external_dependencies(metadata) do
    metadata
    |> Map.get("external_dependencies", [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.map(&external_dependency/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.take(@max_external_dependencies)
  end

  defp external_dependency(dependency) do
    case Map.get(dependency, "name") do
      name when is_binary(name) and name != "" ->
        if String.valid?(name) do
          detail =
            [dependency["header"], dependency["library"]]
            |> Enum.filter(&(is_binary(&1) and String.valid?(&1) and &1 != ""))
            |> Enum.join(", ")

          %{name: name, detail: detail}
        end

      _ ->
        nil
    end
  end
end
