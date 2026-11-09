defmodule LuxpkgsWeb.NavBar do
  use LuxpkgsWeb, :html

  alias Phoenix.LiveView.JS

  alias Luxpkgs.Accounts.User
  alias Luxpkgs.Admin

  def navbar(%{current_scope: _} = assigns) do
    ~H"""
    <!-- Mobile menu backdrop overlay -->
    <div
      id="mobile-menu-backdrop"
      class="hidden fixed inset-0 bg-black/50 z-40 md:hidden opacity-0"
      phx-click={close_mobile_menu()}
    >
    </div>

    <nav class="navbar bg-base-300 shadow-sm px-4 md:text-lg relative z-50">
      <div class="navbar-start flex-1">
        <.link class="flex items-center text-xl" navigate={~p"/"}>
          <.logo class="h-6 md:h-8 w-auto mr-2" />
          <span class="font-semibold">Luxpkgs</span>
        </.link>
      </div>

      <!-- Global menu items (always there no matters if mobile or desktop) -->
      <div class="flex items-center space-x-2 md:space-x-6">
        <LuxpkgsWeb.Layouts.theme_toggle />
        <button
          id="mobile-menu-toggle"
          class="md:hidden btn btn-ghost rounded-field text-grey hover:text-base-content p-2 min-h-11 min-w-11"
          aria-expanded="false"
          aria-controls="mobile-menu"
          aria-label="Menu"
          phx-click={toggle_mobile_menu()}
        >
          <.icon id="menu-icon" name={:menu_deep} type={:outline} class="size-6" />
          <.icon id="close-icon" name={:x} type={:outline} class="hidden hover:text-error size-6" />
        </button>
      </div>

      <.desktop_menu current_scope={@current_scope} />
      <.mobile_menu current_scope={@current_scope} />
    </nav>
    """
  end

  defp account_dropdown(%{current_scope: current_scope} = assigns) do
    assigns =
      assigns
      |> assign(
        :unique_username,
        if(current_scope, do: User.unique_username(current_scope.user), else: nil)
      )
      |> assign(
        :admin?,
        current_scope && not is_nil(Admin.get_active_admin_for_user(current_scope.user))
      )

    ~H"""
    <div class="dropdown dropdown-end w-full sm:w-auto">
      <%= if @current_scope do %>
        <button
          type="button"
          tabindex="0"
          class="btn btn-ghost btn-block justify-start text-grey hover:text-primary rounded-field px-1 sm:px-4"
        >
          <%= if @current_scope.user.avatar_url do %>
            <img
              src={@current_scope.user.avatar_url}
              alt={@unique_username}
              class="w-6 h-6 rounded-full"
            />
          <% else %>
            <.icon name={:user_circle} type={:outline} />
          <% end %>
          <span class="mt-px">
            {String.slice(@unique_username, 0..20)}
          </span>
        </button>
      <% else %>
        <.link
          class="btn btn-ghost btn-block justify-start text-grey hover:text-primary rounded-field px-1 sm:px-4"
          navigate={~p"/login"}
        >
          <.icon name={:user_circle} type={:outline} />
          <span class="mt-px">
            Log In
          </span>
        </.link>
      <% end %>
      <ul
        :if={@current_scope}
        tabindex="0"
        class="menu dropdown-content bg-base-200 border border-base-300 rounded-box z-1 mt-4 w-52 p-2 shadow-sm"
      >
        <li>
          <.link navigate={~p"/users/#{@unique_username}"}>Profile</.link>
        </li>
        <li>
          <.link navigate={~p"/settings"}>Settings</.link>
        </li>
        <li>
          <.link navigate={~p"/keys"}>API keys</.link>
        </li>
        <li :if={@admin?}>
          <.link navigate={~p"/admin"}>Admin panel</.link>
        </li>
        <hr class="text-base-300 mt-1 mb-1" />
        <li>
          <.link href={~p"/logout"} method="delete">Log out</.link>
        </li>
      </ul>
    </div>
    """
  end

  defp desktop_menu(assigns) do
    ~H"""
    <div class="hidden md:flex items-center space-x-2">
      <ul class="menu menu-horizontal px-1 space-x-2">
        <li>
          <.link
            class="btn btn-ghost text-grey hover:text-primary"
            href="https://lumen-oss.github.io"
            target="_blank"
            rel="noopener"
          >
            <.icon name={:book_2} type={:outline} />
            <span class="mt-px">Docs</span>
          </.link>
        </li>
        <li>
          <.link
            class="btn btn-ghost text-grey hover:text-primary"
            navigate={~p"/donate"}
          >
            <.icon name={:heart} type={:outline} />
            <span class="mt-px">Donate</span>
          </.link>
        </li>
        <li>
          <.link
            class="btn btn-ghost text-grey hover:text-primary"
            href="https://github.com/lumen-oss/luxpkgs"
            target="_blank"
            rel="noopener"
          >
            <.icon name={:brand_github} type={:outline} />
            <span class="mt-px">Source</span>
          </.link>
        </li>
        <.account_dropdown current_scope={@current_scope} />
      </ul>
    </div>
    """
  end

  defp mobile_menu(assigns) do
    ~H"""
    <div
      id="mobile-menu"
      class="hidden absolute top-full left-0 right-0 bg-base-200 rounded-b-lg shadow-xl border-t border-base-content/10 z-50 opacity-0 scale-95"
      role="navigation"
      aria-label="Mobile navigation"
      phx-window-keydown={close_mobile_menu()}
      phx-key="Escape"
    >
      <div class="px-4 py-3">
        <ul class="menu menu-vertical w-full space-y-1">
          <li>
            <.link
              class="btn btn-ghost justify-start text-grey hover:text-primary w-full min-h-12 px-4"
              href="https://lumen-oss.github.io"
              target="_blank"
              rel="noopener"
              phx-click={close_mobile_menu()}
            >
              <.icon name={:book_2} type={:outline} class="size-5" />
              <span class="ml-3">Documentation</span>
            </.link>
          </li>
          <li>
            <.link
              class="btn btn-ghost justify-start text-grey hover:text-primary w-full min-h-12 px-4"
              navigate={~p"/donate"}
              phx-click={close_mobile_menu()}
            >
              <.icon name={:heart} type={:outline} class="size-5" />
              <span class="ml-3">Donate</span>
            </.link>
          </li>
          <li>
            <.link
              class="btn btn-ghost justify-start text-grey hover:text-primary w-full min-h-12 px-4"
              href="https://github.com/lumen-oss/luxpkgs"
              target="_blank"
              rel="noopener"
              phx-click={close_mobile_menu()}
            >
              <.icon name={:brand_github} type={:outline} class="size-5" />
              <span class="ml-3">Source Code</span>
            </.link>
          </li>
          <div class="divider my-2"></div>
          <li>
            <.account_dropdown current_scope={@current_scope} />
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp toggle_mobile_menu do
    # Scale + fade for the animations, overflow-hidden to prevent scrolling when open
    JS.toggle(
      to: "#mobile-menu",
      in: {"ease-out duration-200", "opacity-0 scale-95", "opacity-100 scale-100"},
      out: {"ease-in duration-150", "opacity-100 scale-100", "opacity-0 scale-95"}
    )
    |> JS.toggle(
      to: "#mobile-menu-backdrop",
      in: {"ease-out duration-200", "opacity-0", "opacity-100"},
      out: {"ease-in duration-150", "opacity-100", "opacity-0"}
    )
    |> JS.toggle_class("hidden", to: "#menu-icon")
    |> JS.toggle_class("hidden", to: "#close-icon")
    |> JS.toggle_class("overflow-hidden", to: "body")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"})
  end

  defp close_mobile_menu do
    JS.hide(
      to: "#mobile-menu",
      transition: {"ease-in duration-150", "opacity-100 scale-100", "opacity-0 scale-95"}
    )
    |> JS.hide(
      to: "#mobile-menu-backdrop",
      transition: {"ease-in duration-150", "opacity-100", "opacity-0"}
    )
    |> JS.remove_class("hidden", to: "#menu-icon")
    |> JS.add_class("hidden", to: "#close-icon")
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "#mobile-menu-toggle")
  end
end
