defmodule Luxpkgs.Admin do
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Luxpkgs.Accounts
  alias Luxpkgs.Accounts.User
  alias Luxpkgs.Admin.Admin
  alias Luxpkgs.Audit
  alias Luxpkgs.Repo

  @roles [:admin, :moderator]
  @admins_topic "admin:admins"

  def roles, do: @roles

  def grant_by_user_id(user_id, role) do
    with {:ok, user_id} <- normalize_user_id(user_id),
         {:ok, role} <- normalize_role(role),
         %User{} = user <- Accounts.get_user(user_id),
         :ok <- ensure_not_deleted(user) do
      grant(user, role)
    else
      nil -> {:error, :user_not_found}
      error -> error
    end
  end

  def revoke_by_user_id(user_id) do
    with {:ok, user_id} <- normalize_user_id(user_id),
         %Admin{} = admin <- Repo.get_by(Admin, user_id: user_id) do
      admin = Repo.preload(admin, :user)

      if admin.active do
        revoke(admin)
      else
        {:ok, admin}
      end
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def list do
    Repo.all(
      from admin in Admin,
        order_by: [asc: admin.inserted_at, asc: admin.id],
        preload: [:user]
    )
  end

  def get_active_admin_for_user(%User{id: user_id}), do: get_active_admin_for_user(user_id)

  def get_active_admin_for_user(user_id) when is_integer(user_id) and user_id > 0 do
    Repo.one(
      from admin in Admin,
        where: admin.user_id == ^user_id and admin.active == true,
        preload: [:user]
    )
  end

  def get_active_admin_for_user(_user_id), do: nil

  defp grant(user, role) do
    case Repo.get_by(Admin, user_id: user.id) do
      nil ->
        Multi.new()
        |> Multi.insert(
          :admin,
          Admin.changeset(%Admin{}, %{user_id: user.id, role: role, active: true})
        )
        |> Multi.insert(
          :audit,
          Audit.changeset(audit_attrs("admin.granted", user, %{"role" => to_string(role)}))
        )
        |> transact()

      %Admin{active: false} = admin ->
        Multi.new()
        |> Multi.update(:admin, Admin.changeset(admin, %{role: role, active: true}))
        |> Multi.insert(
          :audit,
          Audit.changeset(
            audit_attrs("admin.granted", user, %{
              "role" => to_string(role),
              "reactivated" => true
            })
          )
        )
        |> transact()

      %Admin{active: true, role: ^role} = admin ->
        {:ok, Repo.preload(admin, :user)}

      %Admin{active: true} = admin ->
        Multi.new()
        |> Multi.update(:admin, Admin.changeset(admin, %{role: role}))
        |> Multi.insert(
          :audit,
          Audit.changeset(
            audit_attrs("admin.role_changed", user, %{
              "from" => to_string(admin.role),
              "to" => to_string(role)
            })
          )
        )
        |> transact()
    end
  end

  defp revoke(admin) do
    Multi.new()
    |> Multi.update(:admin, Admin.changeset(admin, %{active: false}))
    |> Multi.insert(
      :audit,
      Audit.changeset(
        audit_attrs("admin.revoked", admin.user, %{"role" => to_string(admin.role)})
      )
    )
    |> transact()
  end

  defp transact(multi) do
    case Repo.transaction(multi) do
      {:ok, changes} ->
        admin = Repo.preload(changes.admin, :user)
        if changes[:audit], do: Audit.broadcast(changes.audit)
        broadcast_admin_change(admin)
        {:ok, admin}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp audit_attrs(action, user, metadata) do
    %{
      type: :auth,
      action: action,
      actor_admin_id: nil,
      actor_label: "cli",
      target_type: "user",
      target_id: user.id,
      target_label: user.username,
      metadata: metadata
    }
  end

  defp broadcast_admin_change(admin) do
    Phoenix.PubSub.broadcast(Luxpkgs.PubSub, @admins_topic, {:admin_changed, admin})
  end

  defp normalize_user_id(user_id) when is_integer(user_id) and user_id > 0, do: {:ok, user_id}
  defp normalize_user_id(_user_id), do: {:error, :invalid_user_id}

  defp normalize_role(role) when role in @roles, do: {:ok, role}

  defp normalize_role(role) when is_binary(role) do
    case Enum.find(@roles, &(Atom.to_string(&1) == role)) do
      nil -> {:error, :invalid_role}
      found_role -> {:ok, found_role}
    end
  end

  defp normalize_role(_role), do: {:error, :invalid_role}

  defp ensure_not_deleted(%User{provider: "deleted"}), do: {:error, :deleted_user}
  defp ensure_not_deleted(%User{}), do: :ok
end
