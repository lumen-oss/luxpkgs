defmodule LuxpkgsWeb.UserLive.ProvideEmail do
  use LuxpkgsWeb, :live_view
  alias Luxpkgs.Accounts.User

  def mount(_params, session, socket) do
    oauth_data = session["oauth_signup_token"]

    changeset = User.email_changeset(%User{}, %{})

    {:ok,
     socket
     |> assign(:oauth_data, oauth_data)
     |> assign(:provider, oauth_data.provider |> to_string() |> String.capitalize())
     |> assign(:form, to_form(changeset))
     |> assign(:page_title, "Provide Email")}
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      %User{}
      |> User.email_changeset(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={nil}>
      <div class="flex-1 flex bg-base-200">
        <div class="page-container max-w-md space-y-8 py-16">
          <div class="text-center space-y-8">
            <div class="flex justify-center">
              <div class="bg-primary p-6">
                <.icon name={:mail} type={:outline} class="size-8 text-primary-content" />
              </div>
            </div>

            <.header class="text-center">
              <h1 class="text-2xl font-bold text-base-content">Email Required</h1>
              <:subtitle>
                <div class="mt-4 text-base text-base-content/70">
                  Your <span class="font-semibold text-primary">{@provider}</span>
                  account doesn't have a public email address.
                  <br />Please provide an email to complete your registration.
                </div>
              </:subtitle>
            </.header>
          </div>

          <%!-- Provider indicator --%>
          <div class="flex items-center justify-center space-x-4 py-6 px-6 bg-base-100 border border-base-300 rounded-box">
            <%= if @oauth_data.provider == :github do %>
              <.icon name={:brand_github} type={:filled} class="size-5 text-base-content" />
            <% else %>
              <.icon name={:code} type={:outline} class="size-5 text-base-content" />
            <% end %>
            <span class="text-sm font-medium text-base-content">
              Authenticated via {@provider}
            </span>
            <.icon name={:check} type={:outline} class="size-5 text-success" />
          </div>

          <div class="bg-base-100 border border-base-300 rounded-box p-8">
            <.form
              for={@form}
              id="email_form"
              action={~p"/complete-signup"}
              method="post"
              phx-change="validate"
              class="flex flex-col gap-6"
            >
              <.input
                field={@form[:email]}
                type="email"
                label="Email Address"
                placeholder="your.email@example.com"
                required
                autocomplete="email"
                class="input min-w-full"
              />
              <p class="text-sm text-base-content/70">
                This email will be used for account notifications and recovery.
              </p>

              <button type="submit" class="btn btn-primary min-w-full font-semibold">
                <.icon name={:user_plus} type={:outline} class="size-4" /> Complete Registration
              </button>
            </.form>
          </div>

          <div class="text-center">
            <.link
              navigate={~p"/login"}
              class="link link-hover inline-flex items-center text-sm font-medium"
            >
              <.icon name={:arrow_left} type={:outline} class="size-4 mr-2" />
              Cancel and try a different login method
            </.link>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
