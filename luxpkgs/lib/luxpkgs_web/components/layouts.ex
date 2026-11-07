defmodule LuxpkgsWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is rendered as component
  in regular views and live views.
  """
  use LuxpkgsWeb, :html

  import LuxpkgsWeb.NavBar

  embed_templates("layouts/*")

  def app(%{current_scope: _} = assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <a
        href="#main"
        class="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-50 focus:rounded-box focus:bg-base-100 focus:px-4 focus:py-2 focus:text-base-content focus:shadow-md"
      >
        Skip to content
      </a>
      <header>
        <.navbar current_scope={@current_scope} />
      </header>

      <main
        id="main"
        tabindex="-1"
        class="grow flex flex-col transition-all duration-500 ease-in-out opacity-0 phx-page-loading:opacity-0 motion-reduce:transition-none motion-reduce:opacity-100"
        phx-mounted={JS.remove_class("opacity-0")}
      >
        {render_slot(@inner_block)}
      </main>

      <footer>
        <.footer />
      </footer>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")
  attr(:id, :string, default: "flash-group", doc: "the optional id of flash container")

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} phx-mounted={show("#flash-info")} />
      <.flash kind={:error} flash={@flash} phx-mounted={show("#flash-error")} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <%!-- <span class="inline-flex items-baseline"> --%>
        <%!--   <.icon name={:refresh} type={:outline} class="ml-1 size-3 motion-safe:animate-spin" /> --%>
        <%!-- </span> --%>
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Hang in there while we get back on track")}
        <%!-- <span class="inline-flex items-baseline"> --%>
        <%!--   <.icon name={:refresh} type={:outline} class="ml-1 size-3 motion-safe:animate-spin" /> --%>
        <%!-- </span> --%>
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  attr :id, :string, default: "theme-dropdown"
  attr :dropdown_class, :string, default: "dropdown-end md:dropdown-center"

  def theme_toggle(assigns) do
    ~H"""
    <details id={@id} class={["dropdown", @dropdown_class]}>
      <summary class="btn btn-ghost btn-square list-none" aria-label="Theme">
        <span class="relative inline-flex size-5">
          <.icon
            name={:device_desktop_cog}
            type={:outline}
            class="size-5 in-data-theme:hidden"
          />
          <.icon
            name={:sun}
            type={:outline}
            class="size-5 hidden in-data-[theme=light]:inline"
          />
          <.icon
            name={:moon_stars}
            type={:outline}
            class="size-5 hidden in-data-[theme=dark]:inline"
          />
        </span>
      </summary>
      <ul class="dropdown-content menu bg-base-200 border border-base-300 rounded-box z-50 shadow-2xl mt-2 p-2 w-48 text-sm">
        <li>
          <button
            phx-click={
              JS.dispatch("phx:set-theme", detail: %{theme: "system"})
              |> JS.remove_attribute("open", to: "##{@id}")
            }
            aria-label="System"
          >
            <span class="relative inline-flex size-5">
              <.icon name={:device_desktop_cog} type={:outline} class="size-4" />
            </span>
            System <.icon name={:check} type={:outline} class="ml-auto size-4 in-data-theme:hidden" />
          </button>
        </li>
        <li>
          <button
            phx-click={
              JS.dispatch("phx:set-theme", detail: %{theme: "light"})
              |> JS.remove_attribute("open", to: "##{@id}")
            }
            aria-label="Light"
          >
            <.icon name={:sun} type={:outline} class="size-4" /> Light
            <.icon
              name={:check}
              type={:outline}
              class="ml-auto size-4 hidden in-data-[theme=light]:inline"
            />
          </button>
        </li>
        <li>
          <button
            phx-click={
              JS.dispatch("phx:set-theme", detail: %{theme: "dark"})
              |> JS.remove_attribute("open", to: "##{@id}")
            }
            aria-label="Dark"
          >
            <.icon name={:moon_stars} type={:outline} class="size-4" /> Dark
            <.icon
              name={:check}
              type={:outline}
              class="ml-auto size-4 hidden in-data-[theme=dark]:inline"
            />
          </button>
        </li>
      </ul>
    </details>
    """
  end
end
