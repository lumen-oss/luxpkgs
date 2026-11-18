defmodule Luxpkgs.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Ecto.Multi
  alias Luxpkgs.Repo

  alias Luxpkgs.Accounts.{User, UserIdentity, UserToken, TotpSecret, TotpBackupCode}
  alias Luxpkgs.Admin
  alias Luxpkgs.Admin.Admin, as: AdminRow
  alias Luxpkgs.Audit
  alias Luxpkgs.Packages.Package

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  def get_user_by_auth(%Ueberauth.Auth{} = auth) do
    provider = to_string(auth.provider)

    case find_identity(provider, auth) do
      %UserIdentity{} = identity ->
        remember_uid(identity, auth.uid)
        Repo.get(User, identity.user_id)

      nil ->
        nil
    end
  end

  defp find_identity(provider, %Ueberauth.Auth{} = auth) do
    identity_by_uid(provider, auth.uid) ||
      identity_by_username(provider, auth.info.nickname) ||
      identity_by_email(provider, auth.info.email)
  end

  defp identity_by_uid(_provider, nil), do: nil

  defp identity_by_uid(provider, uid), do: Repo.get_by(UserIdentity, provider: provider, uid: uid)

  # GitHub calls the account name "nickname". A username match may only claim an
  # identity that has no uid yet, so a reclaimed handle cannot take over an account.
  defp identity_by_username(_provider, nil), do: nil

  defp identity_by_username(provider, username) do
    Repo.one(
      from i in UserIdentity,
        where: i.provider == ^provider and i.username == ^username and is_nil(i.uid)
    )
  end

  # Backfilled identities have no uid. The same-provider email fallback lets its
  # owner claim one once; a row from another provider must never be matched.
  defp identity_by_email(_provider, nil), do: nil

  defp identity_by_email(provider, email) do
    with %User{id: user_id} <- Repo.get_by(User, provider: provider, email: email),
         %UserIdentity{uid: nil} = identity <-
           Repo.get_by(UserIdentity, user_id: user_id, provider: provider) do
      identity
    else
      _ -> nil
    end
  end

  defp remember_uid(%UserIdentity{uid: nil} = identity, uid) when is_binary(uid) do
    identity
    |> Ecto.Changeset.change(uid: uid)
    |> Repo.update()
    |> case do
      {:ok, _identity} ->
        :ok

      {:error, changeset} ->
        Logger.error(
          "Could not store the OAuth uid on identity #{identity.id}: #{inspect(changeset.errors)}"
        )

        :ok
    end
  end

  defp remember_uid(_identity, _uid), do: :ok

  def user_count do
    Repo.one(from(u in User, select: count(u.id)))
  end

  @doc """
  Returns a paginated list of users for the admin area.
  """
  def list_users(opts \\ []) do
    page_size = 20
    page = max(Keyword.get(opts, :page, 1), 1)
    search = opts |> Keyword.get(:search, "") |> to_string() |> String.trim()

    query =
      User
      |> filter_user_sentinel(Keyword.get(opts, :include_deleted, false))
      |> filter_user_status(Keyword.get(opts, :status, "all"))
      |> filter_user_role(Keyword.get(opts, :role, "all"))
      |> filter_user_search(search)

    total_count = Repo.aggregate(query, :count, :id)

    users =
      query
      |> order_by([u], desc: u.inserted_at, desc: u.id)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload(:admin)
      |> Repo.all()

    %{
      users: users,
      total_count: total_count,
      page: page,
      page_size: page_size,
      total_pages: max(ceil(total_count / page_size), 1)
    }
  end

  defp filter_user_sentinel(query, true), do: query
  defp filter_user_sentinel(query, false), do: where(query, [u], u.provider != "deleted")

  defp filter_user_status(query, "active"), do: where(query, [u], is_nil(u.suspended_at))
  defp filter_user_status(query, "suspended"), do: where(query, [u], not is_nil(u.suspended_at))
  defp filter_user_status(query, _status), do: query

  defp filter_user_role(query, "admin") do
    query
    |> join(:inner, [u], a in AdminRow, on: a.user_id == u.id)
    |> where([_u, a], a.active == true and a.role == :admin)
  end

  defp filter_user_role(query, "moderator") do
    query
    |> join(:inner, [u], a in AdminRow, on: a.user_id == u.id)
    |> where([_u, a], a.active == true and a.role == :moderator)
  end

  defp filter_user_role(query, "none") do
    query
    |> join(:left, [u], a in AdminRow, on: a.user_id == u.id and a.active == true)
    |> where([_u, a], is_nil(a.id))
  end

  defp filter_user_role(query, _role), do: query

  defp filter_user_search(query, "") do
    query
  end

  defp filter_user_search(query, search) do
    pattern = "%#{search}%"

    where(
      query,
      [u],
      ilike(u.username, ^pattern) or ilike(u.email, ^pattern) or ilike(u.aka, ^pattern)
    )
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  def get_user(id), do: Repo.get(User, id)

  ## User registration

  @doc """
  Registers a user from a successful oauth login.

  ## Examples

      iex> register_user(%Ueberauth.Auth{} = auth)
      {:ok, %User{}}
  """
  def register_user(%Ueberauth.Auth{} = auth) do
    Multi.new()
    |> Multi.insert(:user, User.oauth_changeset(%User{}, auth))
    |> Multi.insert(:identity, fn %{user: user} ->
      UserIdentity.changeset(%UserIdentity{user_id: user.id}, identity_attrs(auth))
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Refreshes the identity and the display copy on the user after a login.
  """
  def sync_profile(%User{} = user, %Ueberauth.Auth{} = auth) do
    with %UserIdentity{} = identity <- upsert_identity(user, auth) do
      sync_display_copy(user, identity)
    end

    :ok
  end

  defp upsert_identity(%User{} = user, %Ueberauth.Auth{} = auth) do
    identity =
      Repo.get_by(UserIdentity, user_id: user.id, provider: to_string(auth.provider)) ||
        %UserIdentity{user_id: user.id}

    attrs = identity_attrs(auth)
    # A stored uid is authoritative; a later login must never replace it.
    attrs = if identity.uid, do: Map.delete(attrs, :uid), else: attrs

    identity
    |> UserIdentity.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, identity} ->
        identity

      {:error, changeset} ->
        Logger.error(
          "Could not sync the identity of user #{user.id}: #{inspect(changeset.errors)}"
        )

        nil
    end
  end

  # The users columns are the display copy of the primary identity.
  defp sync_display_copy(%User{} = user, %UserIdentity{} = identity) do
    if user.provider == identity.provider do
      user
      |> Ecto.Changeset.change(%{
        username: identity.username,
        aka: identity.aka,
        avatar_url: identity.avatar_url
      })
      |> User.validate_avatar_url()
      |> Repo.update()
      |> case do
        {:ok, user} ->
          user

        {:error, changeset} ->
          Logger.error(
            "Could not sync the profile of user #{user.id}: #{inspect(changeset.errors)}"
          )

          user
      end
    end
  end

  defp identity_attrs(%Ueberauth.Auth{} = auth) do
    %{
      provider: to_string(auth.provider),
      uid: auth.uid,
      username: auth.info.nickname,
      aka: auth.info.name,
      avatar_url: auth.info.image
    }
  end

  ## Settings

  @doc """
  Updates the user's avatar URL, e.g. from a fresh OAuth login.
  """
  def update_user_avatar(%User{} = user, avatar_url) when is_binary(avatar_url) do
    user
    |> Ecto.Changeset.change(%{avatar_url: avatar_url})
    |> User.validate_avatar_url()
    |> Repo.update()
  end

  def update_bio(%User{} = user, bio) do
    user
    |> User.bio_changeset(bio)
    |> Repo.update()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Suspension

  @doc """
  Suspends a user, revokes their session tokens, and deactivates their admin row.

  Returns the revoked tokens so callers can disconnect live sockets.
  """
  def suspend_user(%AdminRow{} = actor, %User{} = user, reason) do
    changeset = User.suspend_changeset(user, %{suspension_reason: reason})
    actor = Repo.preload(actor, :user)

    with :ok <- ensure_not_self(actor, user),
         :ok <- ensure_not_last_admin(user),
         :ok <- validate_changeset(changeset) do
      tokens = list_user_tokens(user)

      Multi.new()
      |> Multi.update(:user, changeset)
      |> Multi.update_all(
        :admin,
        from(a in AdminRow, where: a.user_id == ^user.id),
        set: [active: false]
      )
      |> Multi.delete_all(:tokens, from(t in UserToken, where: t.user_id == ^user.id))
      |> Multi.insert(
        :audit,
        Audit.changeset(
          suspension_audit_attrs("user.suspended", actor, user, %{"reason" => reason})
        )
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{user: user, audit: event}} ->
          Audit.broadcast(event)
          {:ok, user, tokens}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Clears a user's suspension. An inactive admin row stays inactive.
  """
  def unsuspend_user(%AdminRow{} = actor, %User{} = user) do
    actor = Repo.preload(actor, :user)

    Multi.new()
    |> Multi.update(:user, User.unsuspend_changeset(user))
    |> Multi.insert(
      :audit,
      Audit.changeset(suspension_audit_attrs("user.unsuspended", actor, user, %{}))
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, audit: event}} ->
        Audit.broadcast(event)
        {:ok, user}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp ensure_not_self(%AdminRow{user_id: id}, %User{id: id}), do: {:error, :self_suspend}
  defp ensure_not_self(_actor, _user), do: :ok

  # shortcut: the last-admin count is read before the transaction, so two concurrent
  # suspensions could both pass it; add a row lock if that becomes possible.
  defp ensure_not_last_admin(user) do
    case Admin.get_admin_for_user(user) do
      %AdminRow{active: true, role: :admin} ->
        if Admin.active_admin_count() <= 1, do: {:error, :last_admin}, else: :ok

      _ ->
        :ok
    end
  end

  defp validate_changeset(changeset) do
    if changeset.valid?, do: :ok, else: {:error, changeset}
  end

  defp suspension_audit_attrs(action, actor, user, metadata) do
    %{
      type: :user,
      action: action,
      actor_admin_id: actor.id,
      actor_label: actor.user.username || actor.user.email,
      target_type: "user",
      target_id: user.id,
      target_label: user.username || user.email,
      metadata: metadata
    }
  end

  ## Account deletion

  @deleted_user_attrs %{
    provider: "deleted",
    username: "deleted",
    aka: "Deleted User",
    email: "deleted@luxpkgs.org"
  }

  @doc """
  Returns the sentinel user that owns packages left behind by deleted accounts.
  """
  def deleted_user do
    Repo.get_by(User, provider: "deleted", username: "deleted") ||
      %User{}
      |> Ecto.Changeset.change(@deleted_user_attrs)
      |> Repo.insert!(on_conflict: :nothing, conflict_target: [:provider, :username])
      |> case do
        %User{id: nil} -> Repo.get_by!(User, provider: "deleted", username: "deleted")
        user -> user
      end
  end

  @doc """
  Returns all tokens belonging to the user.
  """
  def list_user_tokens(%User{} = user) do
    Repo.all(UserToken.by_user_and_contexts_query(user, :all))
  end

  @doc """
  Clears a user's TOTP and backup codes and revokes their session tokens.

  This is the CLI break-glass path for a user who has lost both their
  authenticator and their backup codes.
  """
  def reset_totp(%User{} = user) do
    tokens = list_user_tokens(user)

    Multi.new()
    |> Multi.delete_all(:backup_codes, from(c in TotpBackupCode, where: c.user_id == ^user.id))
    |> Multi.delete_all(:totp_secret, from(t in TotpSecret, where: t.user_id == ^user.id))
    |> Multi.delete_all(:tokens, from(t in UserToken, where: t.user_id == ^user.id))
    |> Multi.insert(
      :audit,
      Audit.changeset(%{
        type: :user,
        action: "user.totp_reset",
        actor_label: "cli",
        target_type: "user",
        target_id: user.id,
        target_label: user.username || user.email,
        metadata: %{}
      })
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{audit: event}} ->
        Audit.broadcast(event)
        {:ok, tokens}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes the user, reassigning their packages to the sentinel account.
  """
  def delete_user(%User{} = user) do
    tokens = list_user_tokens(user)

    Multi.new()
    |> Multi.update_all(
      :reassign_packages,
      from(p in Package, where: p.user_id == ^user.id),
      set: [user_id: deleted_user().id]
    )
    |> Multi.delete(:user, user)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> {:ok, tokens}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end
end
