defmodule LuxpkgsWeb.UserLive.Settings do
  use LuxpkgsWeb, :live_view

  alias Luxpkgs.Accounts.TOTP

  on_mount({LuxpkgsWeb.UserAuth, :require_sudo_mode})

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    bio_count = (user.bio || "") |> String.length()

    {:ok,
     socket
     |> assign(:email_form, nil)
     |> assign(:username_form, nil)
     |> assign(:bio_count, bio_count)
     |> assign(:backup_codes, nil)
     |> assign(:tfa_open, false)
     |> assign(:account_open, true)
     |> assign(:backup_codes_remaining, TOTP.backup_codes_remaining(user))
     |> maybe_reveal_backup_codes(user)}
  end

  defp maybe_reveal_backup_codes(socket, user) do
    with true <- connected?(socket),
         {:ok, codes} when is_list(codes) and codes != [] <-
           Cachex.take(:totp_backup_codes, user.id) do
      socket
      |> assign(:backup_codes, codes)
      |> assign(:tfa_open, true)
      |> assign(:account_open, false)
      |> push_event("scroll-to", %{id: "two-factor-auth"})
    else
      _ -> socket
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="bg-base-100 border-b border-base-300">
        <div class="page-container max-w-5xl py-4 lg:py-6">
          <div class="flex items-center gap-3">
            <div class="w-16 h-16 sm:w-20 sm:h-20 bg-primary/10 border-2 border-primary/20 rounded-full flex items-center justify-center shrink-0">
              <.icon name={:user} type={:outline} class="w-10 h-10 sm:w-12 sm:h-12 text-primary" />
            </div>
            <div>
              <h1 class="text-2xl sm:text-3xl lg:text-4xl font-semibold text-base-content">
                Settings
              </h1>
              <p class="text-sm sm:text-base text-base-content/70">
                Manage your profile and account preferences
              </p>
            </div>
          </div>
        </div>
      </div>

      <div class="page-container max-w-5xl py-6 lg:py-8">
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Profile Card --%>
          <div class="lg:col-span-1">
            <div class="bg-base-200 border border-base-300 rounded-box p-6 sticky top-6">
              <div class="text-center">
                <%= if @current_scope.user.avatar_url do %>
                  <div class="avatar mb-4">
                    <div class="w-20 rounded-full">
                      <img src={@current_scope.user.avatar_url} alt={@current_scope.user.username} />
                    </div>
                  </div>
                <% else %>
                  <div class="avatar avatar-placeholder mb-4">
                    <div class="w-20 bg-primary/10 border-2 border-primary/20 rounded-full">
                      <span class="text-3xl font-bold text-primary">
                        {String.first(@current_scope.user.username)}
                      </span>
                    </div>
                  </div>
                <% end %>
                <h3 class="text-lg font-semibold text-base-content mb-1">
                  {@current_scope.user.username}
                </h3>
                <p class="text-sm text-base-content/70 mb-4">
                  {@current_scope.user.email}
                </p>
                <%= if @current_scope.user.bio do %>
                  <p class="text-sm text-base-content/80 mb-4">
                    {@current_scope.user.bio}
                  </p>
                <% end %>
              </div>

              <div class="border-t border-base-300 pt-4 space-y-3">
                <div class="flex justify-between items-center">
                  <span class="text-sm text-base-content/70">Member since</span>
                  <span class="text-sm font-medium">{member_since_date(
                    @current_scope.user.inserted_at
                  )}</span>
                </div>
                <div class="flex justify-between items-center">
                  <span class="text-sm text-base-content/70">Auth provider</span>
                  <span class="text-sm font-medium text-primary">GitHub</span>
                </div>
                <div class="flex justify-between items-center">
                  <span class="text-sm text-base-content/70">Account type</span>
                  <span class="text-sm font-medium text-secondary">Standard</span>
                </div>
              </div>
            </div>
          </div>

          <%!-- Settings Sections --%>
          <div class="lg:col-span-2 space-y-4">
            <%!-- Account Section --%>
            <div class="collapse collapse-arrow bg-base-200 border border-base-300">
              <input
                id="account-toggle"
                type="checkbox"
                checked={@account_open}
                phx-click="toggle_account"
              />
              <div class="collapse-title flex items-center gap-3 px-4 sm:px-6">
                <.icon name={:user_circle} type={:outline} class="w-5 h-5 text-primary" />
                <div>
                  <h2 class="font-semibold text-base-content">Account</h2>
                  <p class="text-sm text-base-content/70">Personal information</p>
                </div>
              </div>
              <div class="collapse-content px-4 sm:px-6">
                <div class="space-y-6 pt-2">
                  <%!-- Bio Form --%>
                  <div>
                    <div class="flex items-center justify-between mb-2">
                      <label
                        for="bio-input"
                        class="text-sm font-medium text-base-content/80 block"
                      >
                        Bio
                      </label>
                      <span
                        id="bio-count"
                        aria-live="polite"
                        class="text-xs text-base-content/50 transition-colors duration-150"
                      >
                        {@bio_count}/160
                      </span>
                    </div>
                    <.form
                      for={%{}}
                      id="bio_form"
                      phx-submit="update_bio"
                      class="space-y-3"
                    >
                      <textarea
                        id="bio-input"
                        name="user[bio]"
                        rows="3"
                        maxlength="160"
                        phx-hook="CharacterCounter"
                        data-counter-target="bio-count"
                        data-counter-max="160"
                        placeholder="Tell people about yourself (max 160 characters)"
                        class="textarea textarea-bordered w-full"
                      >{@current_scope.user.bio}</textarea>
                      <button
                        type="submit"
                        class="btn btn-primary btn-sm w-full sm:w-auto"
                        phx-disable-with="Updating..."
                      >
                        <.icon name={:check} type={:outline} class="w-4 h-4" /> Save Changes
                      </button>
                    </.form>
                  </div>

                  <%!-- Email Form --%>
                  <div>
                    <label
                      for="email-input"
                      class="text-sm font-medium text-base-content/80 mb-2 block"
                    >
                      Email Address
                    </label>
                    <.form
                      for={@email_form}
                      id="email_form"
                      phx-submit="update_email"
                      class="space-y-3"
                    >
                      <input
                        id="email-input"
                        type="email"
                        name="user-email"
                        placeholder={@current_scope.user.email}
                        class="input input-bordered w-full"
                        autocomplete="email"
                        required
                      />
                      <button
                        type="submit"
                        class="btn btn-primary btn-sm w-full sm:w-auto"
                        phx-disable-with="Updating..."
                      >
                        <.icon name={:check} type={:outline} class="w-4 h-4" /> Save Changes
                      </button>
                    </.form>
                  </div>

                  <%!-- Username Form --%>
                  <div>
                    <label
                      for="username-input"
                      class="text-sm font-medium text-base-content/80 mb-2 block"
                    >
                      Username
                    </label>
                    <.form
                      for={@username_form}
                      id="username_form"
                      phx-submit="update_username"
                      class="space-y-3"
                    >
                      <input
                        id="username-input"
                        type="text"
                        name="user-name"
                        placeholder={@current_scope.user.username}
                        class="input input-bordered w-full"
                        autocomplete="username"
                        required
                      />
                      <button
                        type="submit"
                        class="btn btn-primary btn-sm w-full sm:w-auto"
                        phx-disable-with="Updating..."
                      >
                        <.icon name={:check} type={:outline} class="w-4 h-4" /> Save Changes
                      </button>
                    </.form>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Notifications Section --%>
            <div class="collapse collapse-arrow bg-base-200 border border-base-300">
              <input type="checkbox" />
              <div class="collapse-title flex items-center gap-3 px-4 sm:px-6">
                <.icon name={:bell} type={:outline} class="w-5 h-5 text-primary" />
                <div>
                  <h2 class="font-semibold text-base-content">Notifications</h2>
                  <p class="text-sm text-base-content/70">Email and push preferences</p>
                </div>
              </div>
              <div class="collapse-content px-4 sm:px-6">
                <div class="space-y-6 pt-2">
                  <div class="flex items-center justify-between py-2">
                    <div>
                      <p class="text-sm font-medium text-base-content">Email Notifications</p>
                      <p class="text-xs text-base-content/70">Receive updates about your packages</p>
                    </div>
                    <input type="checkbox" class="toggle toggle-primary" checked />
                  </div>
                  <div class="flex items-center justify-between py-2">
                    <div>
                      <p class="text-sm font-medium text-base-content">Package Updates</p>
                      <p class="text-xs text-base-content/70">Get notified about new releases</p>
                    </div>
                    <input type="checkbox" class="toggle toggle-primary" checked />
                  </div>
                </div>
              </div>
            </div>

            <%!-- Two-Factor Authentication Section --%>
            <div
              id="two-factor-auth"
              class="collapse collapse-arrow bg-base-200 border border-base-300"
            >
              <input id="tfa-toggle" type="checkbox" checked={@tfa_open} phx-click="toggle_tfa" />
              <div class="collapse-title flex items-center gap-3 px-4 sm:px-6">
                <.icon name={:shield_check} type={:outline} class="w-5 h-5 text-primary" />
                <div>
                  <h2 class="font-semibold text-base-content">Two-Factor Authentication</h2>
                  <p class="text-sm text-base-content/60">Authenticator app and backup codes</p>
                </div>
              </div>
              <div class="collapse-content px-4 sm:px-6">
                <div class="space-y-6 pt-2">
                  <div class="flex items-center justify-between gap-3">
                    <div>
                      <p class="text-sm font-medium text-base-content">Authenticator app</p>
                      <p class="text-xs text-base-content/60">
                        Required for uploads made with a 2FA key
                      </p>
                    </div>
                    <span class="badge badge-success badge-sm">Enabled</span>
                  </div>

                  <div class="flex items-center justify-between gap-3">
                    <div>
                      <p class="text-sm font-medium text-base-content">Backup codes</p>
                      <p class="text-xs text-base-content/60">
                        {if @backup_codes_remaining == 0,
                          do: "No backup codes left - generate a new set",
                          else: "#{@backup_codes_remaining} of 10 codes remaining"}
                      </p>
                    </div>
                    <span class={[
                      "badge badge-sm",
                      @backup_codes_remaining == 0 && "badge-error",
                      @backup_codes_remaining > 0 && "badge-success"
                    ]}>
                      {@backup_codes_remaining}
                    </span>
                  </div>

                  <div
                    :if={@backup_codes}
                    id="backup-codes-panel"
                    class="panel-collapse"
                    phx-mounted={JS.transition("animate-panel-in", time: 200)}
                    phx-remove={JS.transition("animate-panel-out", time: 200)}
                  >
                    <div class="bg-warning/10 border border-warning/30 rounded-box p-4 space-y-4">
                      <div class="flex items-start gap-2">
                        <.icon
                          name={:alert_triangle}
                          type={:outline}
                          class="w-4 h-4 text-warning shrink-0 mt-0.5"
                        />
                        <p class="text-sm font-medium text-warning">
                          Save these backup codes now. They are shown only once and each can be used once.
                        </p>
                      </div>

                      <ul
                        phx-no-format
                        class="grid grid-cols-2 gap-2 font-mono text-sm select-all"
                      >
                        <li
                          :for={code <- @backup_codes}
                          class="bg-base-100 border border-warning/30 rounded-box px-3 py-2 text-center"
                        >{TOTP.format_backup_code(code)}</li>
                      </ul>

                      <span id="backup-codes-copy" class="hidden">{Enum.map_join(
                        @backup_codes,
                        "\n",
                        &TOTP.format_backup_code/1
                      )}</span>

                      <div class="flex flex-col sm:flex-row gap-2">
                        <button
                          id="copy-backup-codes"
                          type="button"
                          class="btn btn-neutral btn-sm"
                          phx-click={
                            JS.dispatch("phx:clipcopy", to: "#backup-codes-copy")
                            |> JS.push("copy_codes")
                          }
                        >
                          <.icon name={:clipboard} type={:outline} class="w-4 h-4" /> Copy all
                        </button>
                        <button
                          id="dismiss-backup-codes"
                          type="button"
                          class="btn btn-ghost btn-sm"
                          phx-click="dismiss_backup_codes"
                        >
                          <.icon name={:check} type={:outline} class="w-4 h-4" /> I've saved my codes
                        </button>
                      </div>
                    </div>
                  </div>

                  <div class="flex flex-col sm:flex-row gap-2">
                    <button
                      class="btn btn-neutral btn-sm"
                      onclick="regenerate_backup_codes_modal.showModal()"
                    >
                      <.icon name={:refresh} type={:outline} class="w-4 h-4" />
                      Regenerate Backup Codes
                    </button>
                    <button class="btn btn-error btn-sm" onclick="remove_tfa_modal.showModal()">
                      <.icon name={:trash} type={:outline} class="w-4 h-4" />
                      Remove Two-Factor Authentication
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Advanced Section --%>
            <div class="collapse collapse-arrow bg-base-200 border border-base-300">
              <input type="checkbox" />
              <div class="collapse-title flex items-center gap-3 px-4 sm:px-6">
                <.icon name={:settings} type={:outline} class="w-5 h-5 text-primary" />
                <div>
                  <h2 class="font-semibold text-base-content">Advanced Settings</h2>
                  <p class="text-sm text-base-content/70">Account management</p>
                </div>
              </div>
              <div class="collapse-content px-4 sm:px-6">
                <div class="space-y-6 pt-2">
                  <div class="bg-base-100 border border-base-300 rounded-box p-4 sm:p-6 space-y-4">
                    <div class="flex items-center justify-between gap-3">
                      <div class="flex items-center gap-3">
                        <.icon name={:brand_github} type={:outline} class="w-5 h-5 text-success" />
                        <div>
                          <p class="text-sm font-medium text-base-content">GitHub Account</p>
                          <p class="text-xs text-base-content/70">Authentication provider</p>
                        </div>
                      </div>
                      <span class="badge badge-success badge-sm">Connected</span>
                    </div>
                  </div>
                  <div class="divider"></div>
                  <div class="flex flex-col sm:flex-row justify-end gap-2">
                    <.link href={~p"/auth/github"} class="btn btn-neutral">
                      <.icon name={:refresh} type={:outline} class="w-4 h-4" /> Sync Profile
                    </.link>
                    <button
                      class="btn btn-error"
                      onclick="delete_account_modal.showModal()"
                    >
                      <.icon name={:trash} type={:outline} class="w-4 h-4" /> Delete Account
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <.confirm_modal
        id="delete_account_modal"
        title="Delete Account?"
        form={%{}}
        form_id="delete_account_form"
        submit="delete_account"
      >
        <p class="text-sm text-base-content/80 mb-4">
          This permanently deletes your account and revokes all API keys and sessions. Your packages will remain available and be owned by a deleted user. This cannot be undone.
        </p>
        <.input
          name="confirm"
          type="text"
          label={"Type #{@current_scope.user.username} to confirm"}
          value=""
          placeholder={@current_scope.user.username}
          required
          autocomplete="off"
        />
        <:confirm>
          <button type="submit" class="btn btn-error" phx-disable-with="Deleting...">
            <.icon name={:trash} type={:outline} class="w-4 h-4" /> Delete Account
          </button>
        </:confirm>
      </.confirm_modal>

      <dialog
        id="regenerate_backup_codes_modal"
        class="modal"
        phx-update="ignore"
        phx-hook="Dialog"
        aria-labelledby="regenerate_backup_codes_modal_title"
      >
        <div class="modal-box">
          <h3
            id="regenerate_backup_codes_modal_title"
            class="text-lg font-bold text-base-content mb-4"
          >
            Regenerate backup codes?
          </h3>
          <p class="text-sm text-base-content/80 mb-6">
            This invalidates every existing backup code. Enter a code from your authenticator app, or one of your current backup codes, to continue.
          </p>
          <.form
            for={%{}}
            id="regenerate_backup_codes_form"
            phx-submit="regenerate_backup_codes"
            class="space-y-4"
          >
            <.input
              name="code"
              type="text"
              label="Verification Code"
              value=""
              placeholder="6-digit code or backup code"
              required
              autocomplete="one-time-code"
            />
            <div class="modal-action">
              <button
                type="button"
                class="btn btn-neutral mr-3"
                onclick="regenerate_backup_codes_modal.close()"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="btn btn-primary"
                phx-disable-with="Regenerating..."
              >
                <.icon name={:refresh} type={:outline} class="w-4 h-4" /> Regenerate Codes
              </button>
            </div>
          </.form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button>close</button>
        </form>
      </dialog>

      <.confirm_modal
        id="remove_tfa_modal"
        title="Remove two-factor authentication?"
        form={%{}}
        form_id="remove_tfa_form"
        submit="remove_tfa"
      >
        <p class="text-sm text-base-content/80 mb-6">
          Your authenticator secret and all backup codes will be deleted, and you will be asked to set two-factor authentication up again. Enter a code from your authenticator app, or one of your current backup codes, to continue.
        </p>
        <.input
          name="code"
          type="text"
          label="Verification Code"
          value=""
          placeholder="6-digit code or backup code"
          required
          autocomplete="one-time-code"
        />
        <:confirm>
          <button type="submit" class="btn btn-error" phx-disable-with="Removing...">
            <.icon name={:trash} type={:outline} class="w-4 h-4" /> Remove
          </button>
        </:confirm>
      </.confirm_modal>
    </Layouts.app>
    """
  end

  def handle_event("update_bio", %{"user" => %{"bio" => bio}}, socket) do
    user = socket.assigns.current_scope.user

    case Luxpkgs.Accounts.update_bio(user, bio) do
      {:ok, user} ->
        socket =
          if Luxpkgs.Accounts.User.strip_urls(bio) != bio do
            put_flash(
              socket,
              :info,
              "Bio saved, but links were removed. Links aren't allowed in bios."
            )
          else
            put_flash(socket, :info, "Bio updated successfully.")
          end

        {:noreply,
         socket
         |> assign(:current_scope, Luxpkgs.Accounts.Scope.for_user(user))
         |> assign(:bio_count, String.length(user.bio || ""))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update bio.")}
    end
  end

  def handle_event("regenerate_backup_codes", %{"code" => code}, socket) do
    user = socket.assigns.current_scope.user

    cond do
      throttle_exceeded?(user) ->
        {:noreply,
         socket
         |> close_modal("regenerate_backup_codes_modal")
         |> put_flash(:error, "Too many attempts. Please try again later.")}

      TOTP.verify(user, code) != :ok ->
        {:noreply,
         socket
         |> close_modal("regenerate_backup_codes_modal")
         |> put_flash(:error, "Invalid verification code.")}

      true ->
        codes = TOTP.generate_backup_codes(user)

        {:noreply,
         socket
         |> assign(:backup_codes, codes)
         |> assign(:tfa_open, true)
         |> assign(:backup_codes_remaining, TOTP.backup_codes_remaining(user))
         |> close_modal("regenerate_backup_codes_modal")
         |> put_flash(:info, "New backup codes generated. Save them now.")}
    end
  end

  def handle_event("regenerate_backup_codes", _params, socket) do
    {:noreply,
     socket
     |> close_modal("regenerate_backup_codes_modal")
     |> put_flash(:error, "Enter a verification code to continue.")}
  end

  def handle_event("dismiss_backup_codes", _params, socket) do
    {:noreply, assign(socket, :backup_codes, nil)}
  end

  def handle_event("toggle_tfa", _params, socket) do
    {:noreply, update(socket, :tfa_open, &(not &1))}
  end

  def handle_event("toggle_account", _params, socket) do
    {:noreply, update(socket, :account_open, &(not &1))}
  end

  def handle_event("copy_codes", _params, socket) do
    socket
    |> clear_flash()
    |> put_flash(:info, "Recovery codes copied to clipboard!")
    |> (&{:noreply, &1}).()
  end

  def handle_event("remove_tfa", %{"code" => code}, socket) do
    user = socket.assigns.current_scope.user

    cond do
      throttle_exceeded?(user) ->
        {:noreply,
         socket
         |> close_modal("remove_tfa_modal")
         |> put_flash(:error, "Too many attempts. Please try again later.")}

      TOTP.verify(user, code) != :ok ->
        {:noreply,
         socket
         |> close_modal("remove_tfa_modal")
         |> put_flash(:error, "Invalid verification code.")}

      true ->
        :ok = TOTP.disable(user)

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Two-factor authentication removed. Set it up again to protect your account."
         )
         |> push_navigate(to: ~p"/setup-totp")}
    end
  end

  def handle_event("remove_tfa", _params, socket) do
    {:noreply,
     socket
     |> close_modal("remove_tfa_modal")
     |> put_flash(:error, "Enter a verification code to continue.")}
  end

  def handle_event("delete_account", %{"confirm" => confirm}, socket) do
    user = socket.assigns.current_scope.user

    if confirm == user.username do
      {:ok, tokens} = Luxpkgs.Accounts.delete_user(user)
      LuxpkgsWeb.UserAuth.disconnect_sessions(tokens)

      {:noreply,
       socket
       |> close_modal("delete_account_modal")
       |> put_flash(:info, "Your account has been deleted.")
       |> redirect(to: ~p"/")}
    else
      {:noreply,
       socket
       |> close_modal("delete_account_modal")
       |> put_flash(:error, "Username does not match. Your account was not deleted.")}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp close_modal(socket, id), do: push_event(socket, "close_dialog", %{id: id})

  defp member_since_date(%DateTime{} = date), do: Calendar.strftime(date, "%B %Y")
  defp member_since_date(%NaiveDateTime{} = date), do: Calendar.strftime(date, "%B %Y")
  defp member_since_date(_), do: "Unknown"

  defp throttle_exceeded?(user), do: LuxpkgsWeb.RateLimit.totp_exceeded?(user.id)
end
