defmodule LuxpkgsWeb.UserLive.Login do
  use LuxpkgsWeb, :live_view

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex-1 flex items-center">
        <div class="max-w-sm w-full space-y-4 py-8 mx-auto">
          <.header class="text-center">
            <p>Choose an OAuth Provider</p>
            <:subtitle>
              <%= if @current_scope do %>
                You need to reauthenticate to perform sensitive actions on your account.
              <% else %>
                We don't support password logins for security reasons.
              <% end %>
            </:subtitle>
          </.header>

          <div class="flex flex-col space-y-4">
            <.link
              class="btn btn-primary"
              id="github-login"
              phx-disable-with="Redirecting..."
              navigate={~p"/auth/github"}
            >
              <.icon name={:brand_github} type={:filled} class="size-5" /> GitHub
            </.link>

            <div class="divider text-sm text-base-content/60">or</div>

            <.form
              for={%{}}
              id="atproto-login"
              action={~p"/auth/atproto"}
              method="post"
              class="flex flex-col gap-3"
            >
              <label class="form-control w-full" for="atproto-handle">
                <span class="label-text mb-1">AT Protocol handle</span>
                <input
                  id="atproto-handle"
                  type="text"
                  name="handle"
                  class="input w-full"
                  placeholder="you.bsky.social"
                  autocomplete="username"
                  required
                />
              </label>
              <button
                type="submit"
                class="btn btn-neutral w-full"
                phx-disable-with="Redirecting..."
              >
                <.icon name={:tangled} type={:outline} class="size-5" /> AT Protocol
              </button>
              <p class="text-sm text-base-content/60 text-center">
                Bluesky, Tangled, or any atproto handle
              </p>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
