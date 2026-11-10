defmodule LuxpkgsWeb.UserLive.Keys do
  use LuxpkgsWeb, :live_view

  alias Phoenix.LiveView.JS

  on_mount({LuxpkgsWeb.UserAuth, :require_sudo_mode})

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="bg-base-100 border-b border-base-300">
        <div class="page-container max-w-4xl py-6 lg:py-8">
          <div class="flex flex-col md:flex-row justify-between items-center gap-4 sm:gap-6">
            <div class="flex items-center gap-4 sm:gap-6">
              <div class="w-16 h-16 sm:w-20 sm:h-20 bg-primary/10 border-2 border-primary/20 rounded-full flex items-center justify-center shrink-0">
                <.icon name={:key} type={:outline} class="w-10 h-10 sm:w-12 sm:h-12 text-primary" />
              </div>

              <div class="space-y-1 flex-1">
                <h1 class="text-2xl sm:text-3xl lg:text-4xl font-bold text-base-content">
                  API Keys
                </h1>
                <p class="text-sm sm:text-base text-base-content/70">
                  Generate and manage API keys for programmatic access to your packages
                </p>
              </div>
            </div>

            <div class="w-full sm:w-auto">
              <button
                class="btn btn-primary w-full sm:w-auto"
                onclick="create_key_modal.showModal()"
              >
                <.icon name={:plus} type={:outline} class="w-4 h-4" /> Create API Key
              </button>
            </div>
          </div>
        </div>
      </div>

      <div class="page-container max-w-4xl py-6 lg:py-8">
        <div class="space-y-6">
          <div class="bg-base-200 border border-base-300 rounded-box p-6">
            <div class="flex items-center gap-3 mb-4">
              <.icon name={:info_circle} type={:outline} class="w-5 h-5 text-primary" />
              <h2 class="text-lg font-semibold text-base-content">About API Keys</h2>
            </div>

            <div class="space-y-3 text-sm text-base-content/80">
              <p>
                API keys allow you to authenticate and interact with the Luxpkgs API programmatically.
                Use them to publish packages, manage releases, and access your package data.
              </p>
              <ul phx-no-format class="list-disc list-inside space-y-1 pl-4">
                <li>Keys can be configured to expire between 1-4 weeks for security</li>
                <li>Never share your API keys with anyone - they are more sensitive than a password</li>
                <li>Revoke keys immediately if compromised</li>
              </ul>
            </div>
          </div>

          <div
            :if={@generated_key}
            class="bg-success/5 border border-success/20 rounded-box p-6 shadow-sm"
          >
            <div class="flex items-center justify-between mb-4">
              <div class="flex items-center gap-3">
                <.icon name={:check} type={:outline} class="w-5 h-5 text-success" />
                <h2 class="text-lg font-semibold text-base-content">Your New API Key</h2>
              </div>
              <div class="flex items-center gap-3 text-xs text-base-content/70">
                <div class="flex items-center gap-1">
                  <.icon name={:clock} type={:outline} class="w-3 h-3" />
                  <span phx-no-format>Expires in {if @ttl_weeks == 1, do: "1 week", else: "#{@ttl_weeks} weeks"}</span>
                </div>
                <div class="flex items-center gap-1">
                  <.icon name={:lock} type={:outline} class="w-3 h-3" />
                  <span phx-no-format class={if @read_only, do: "text-warning", else: "text-success"}>{if @read_only, do: "Read-only", else: "Full access"}</span>
                </div>
              </div>
            </div>

            <div class="space-y-3">
              <div class="flex items-center gap-3">
                <code
                  phx-no-format
                  id="generated-key"
                  class="flex-1 text-sm font-mono px-3 py-2 rounded-box bg-base-100 border border-success/20 break-all"
                >{@generated_key}</code>
                <button
                  class="btn btn-neutral btn-sm gap-2"
                  phx-click={JS.dispatch("phx:clipcopy", to: "#generated-key") |> JS.push("copy_key")}
                  title="Copy to clipboard"
                >
                  <.icon name={:clipboard} type={:outline} class="w-4 h-4" /> Copy
                </button>
              </div>

              <div class="flex items-center gap-2 text-xs text-warning">
                <.icon name={:alert_triangle} type={:outline} class="w-4 h-4 shrink-0" />
                <span>This key will only be shown once. Copy it now and store it securely.</span>
              </div>
            </div>
          </div>

          <div class="bg-base-200 border border-base-300 rounded-box p-6">
            <div class="flex items-center gap-3 mb-4">
              <.icon name={:adjustments} type={:outline} class="w-5 h-5 text-secondary" />
              <h2 class="text-lg font-semibold text-base-content">Key Management</h2>
            </div>

            <p class="text-sm text-base-content/70 mb-4">
              Manage your existing API keys and revoke access when needed.
            </p>

            <div class="space-y-3">
              <button
                phx-no-format
                class="btn btn-error w-full sm:w-auto"
                onclick="revoke_key_modal.showModal()"
              >
                <.icon name={:ban} type={:outline} class="w-4 h-4" /> Revoke API Key</button>

              <p phx-no-format class="text-xs text-base-content/70">Enter a key to revoke its access immediately</p>
            </div>
          </div>
        </div>
      </div>

      <dialog
        id="create_key_modal"
        class="modal"
        phx-update="ignore"
        phx-hook="Dialog"
        aria-labelledby="create_key_modal_title"
      >
        <div class="modal-box">
          <h3 id="create_key_modal_title" class="text-lg font-bold text-base-content mb-4">
            Create New API Key
          </h3>
          <p class="text-sm text-base-content/80 mb-6">
            Configure your new API key settings. Keys will expire based on the selected time period.
          </p>

          <.form for={%{}} phx-submit="generate_key" class="space-y-6">
            <div class="space-y-4">
              <div class="form-control">
                <label
                  id="read_only_label"
                  class="label min-w-full justify-between cursor-pointer transition-colors"
                >
                  <span class="label-text">
                    <div class="flex items-center gap-2">
                      <.icon name={:lock} type={:outline} class="w-4 h-4" /> Read-only
                    </div>
                    <div class="text-xs mt-1">
                      Restrict this key to read-only operations
                    </div>
                  </span>
                  <.input
                    type="checkbox"
                    name="read_only"
                    class="toggle toggle-warning"
                    checked={@read_only}
                    phx-click={JS.toggle_class("text-warning", to: "#read_only_label")}
                  />
                </label>
              </div>

              <.input
                name="ttl_weeks"
                type="select"
                label="Key Expiration"
                value={@ttl_weeks}
                options={[
                  {"1 week", 1},
                  {"2 weeks", 2},
                  {"3 weeks", 3},
                  {"4 weeks (maximum)", 4}
                ]}
              />
              <div class="flex items-center gap-1 text-xs text-base-content/70 mt-1">
                <.icon name={:clock} type={:outline} class="w-3 h-3" />
                Select how long this key should remain valid
              </div>

              <div class="form-control">
                <label
                  id="require_tfa_label"
                  class={[
                    "label min-w-full justify-between cursor-pointer transition-colors",
                    @require_tfa && "text-primary"
                  ]}
                >
                  <span class="label-text">
                    <div class="flex items-center gap-2">
                      <.icon name={:shield_check} type={:outline} class="w-4 h-4" /> Require 2FA
                    </div>
                    <div class="text-xs mt-1">Require TOTP code for uploads with this key</div>
                  </span>
                  <input
                    type="checkbox"
                    name="require_tfa"
                    value="true"
                    class="toggle toggle-primary"
                    checked={@require_tfa}
                    phx-click={JS.toggle_class("text-primary", to: "#require_tfa_label")}
                  />
                </label>
              </div>
            </div>

            <div class="modal-action">
              <button type="button" class="btn btn-neutral mr-3" onclick="create_key_modal.close()">
                Cancel
              </button>
              <button type="submit" class="btn btn-primary" phx-disable-with="Generating...">
                <.icon name={:key} type={:outline} class="w-4 h-4" /> Generate Key
              </button>
            </div>
          </.form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button>close</button>
        </form>
      </dialog>

      <.confirm_modal id="revoke_key_modal" title="Revoke API Key" form={%{}} submit="revoke_key">
        <p class="text-sm text-base-content/80 mb-4">
          Revoked API keys have zero permissions and cannot be used again.
        </p>

        <.input
          name="revoked_key"
          type="text"
          label="API Key"
          value=""
          placeholder="Enter the API key to revoke..."
          required
        />

        <:confirm>
          <button type="submit" class="btn btn-error" phx-disable-with="Revoking...">
            <.icon name={:trash} type={:outline} class="w-4 h-4" /> Revoke Key
          </button>
        </:confirm>
      </.confirm_modal>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:generated_key, nil)
     |> assign(:read_only, false)
     |> assign(:ttl_weeks, Application.get_env(:luxpkgs, :key_ttl_weeks_default, 4))
     |> assign(:require_tfa, true)}
  end

  def handle_event(
        "generate_key",
        %{"read_only" => read_only, "ttl_weeks" => ttl_weeks} = params,
        socket
      ) do
    user = socket.assigns.current_scope.user
    true = user != nil

    read_only = read_only == "true"
    ttl_weeks = String.to_integer(ttl_weeks)
    # Ensure TTL is within allowed range (1-4 weeks)
    ttl_weeks = max(1, min(Application.get_env(:luxpkgs, :key_ttl_weeks_max, 4), ttl_weeks))
    require_tfa = Map.get(params, "require_tfa") == "true"

    # Never allow unbounded TTL as it will not only be a security risk but also
    # cause us to have to store a potentially infinite amount of revoked tokens in our database.
    # With bounded TTLs we can sweep the database for revoked tokens every 24h or so.
    {:ok, token, _claims} =
      Luxpkgs.Guardian.encode_and_sign(
        user,
        %{allowed_packages: nil, write_restriction: read_only, require_tfa: require_tfa},
        ttl: {ttl_weeks, :weeks}
      )

    {:noreply,
     socket
     |> assign(:generated_key, token)
     |> assign(:read_only, read_only)
     |> assign(:ttl_weeks, ttl_weeks)
     |> assign(:require_tfa, require_tfa)
     |> close_modal("create_key_modal")}
  end

  def handle_event("revoke_key", %{"revoked_key" => revoked_key}, socket) do
    case Luxpkgs.RevokedKeys.create_revoked_key(socket.assigns.current_scope, %{
           revoked_key: revoked_key
         }) do
      {:ok} ->
        {:noreply,
         socket
         |> put_flash(:info, "API key revoked successfully!")
         |> assign(:generated_key, nil)
         |> close_modal("revoke_key_modal")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> close_modal("revoke_key_modal")
         |> put_flash(:error, "Failed to revoke key. Ensure it is valid.")}
    end
  end

  def handle_event("delete_key", _params, socket) do
    {:noreply, socket |> assign(:generated_key, nil)}
  end

  def handle_event("copy_key", _params, socket) do
    socket
    |> clear_flash()
    |> put_flash(:info, "API key copied to clipboard!")
    |> (&{:noreply, &1}).()
  end

  defp close_modal(socket, id), do: push_event(socket, "close_dialog", %{id: id})
end
