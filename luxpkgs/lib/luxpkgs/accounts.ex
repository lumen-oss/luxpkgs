defmodule Luxpkgs.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias Luxpkgs.Repo

  alias Luxpkgs.Accounts.{User, UserToken}
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
    # First, try to find user by provider + username
    # This handles cases where GitHub users don't have public emails
    provider = to_string(auth.provider)

    # Goddamn GitHub naming conventions calling the account name "nickname", and the account nickname "name".
    # NOTE: this might need refactoring later once we add support for more providers.
    username = auth.info.nickname

    case Repo.get_by(User, provider: provider, username: username) do
      %User{} = user ->
        user

      nil ->
        # Fallback to email-based lookup for legacy compatibility
        # NOTE: I'm unsure whether we should keep this fallback or not, but it's here for now.
        if auth.info.email do
          get_user_by_email(auth.info.email)
        else
          nil
        end
    end
  end

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
    %User{}
    |> User.oauth_changeset(auth)
    |> Repo.insert()
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
