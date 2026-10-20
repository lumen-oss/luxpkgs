defmodule Luxpkgs.Admin.Admin do
  use Ecto.Schema
  import Ecto.Changeset

  @roles [:admin, :moderator]

  schema "admins" do
    field :role, Ecto.Enum, values: @roles
    field :active, :boolean, default: true

    belongs_to :user, Luxpkgs.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  def changeset(admin, attrs) do
    admin
    |> cast(attrs, [:user_id, :role, :active])
    |> validate_required([:user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:user_id)
    |> check_constraint(:role, name: :admins_role_must_be_valid)
  end
end
