defmodule Luxpkgs.Accounts.UserIdentity do
  use Ecto.Schema
  import Ecto.Changeset

  alias Luxpkgs.Accounts.User

  schema "user_identities" do
    field :provider, :string
    field :uid, :string
    field :username, :string
    field :aka, :string
    field :avatar_url, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(identity, attrs, opts \\ []) do
    identity
    |> cast(attrs, [:provider, :uid, :username, :aka, :avatar_url])
    |> User.validate_provider()
    |> validate_required([:username])
    |> User.validate_avatar_url(opts)
    |> unique_constraint([:user_id, :provider])
    |> unique_constraint([:provider, :uid])
    |> unique_constraint([:provider, :username])
  end
end
