defmodule Luxpkgs.Accounts.User do
  alias Luxpkgs.Accounts.TotpSecret
  alias Luxpkgs.Repo
  alias Ueberauth.Auth
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "users" do
    field :email, :string
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    # Used to uniquely identify the user in the database
    field :provider, :string
    field :username, :string
    field :aka, :string
    field :avatar_url, :string
    field :bio, :string
    field :suspended_at, :utc_datetime
    field :suspension_reason, :string

    has_one :admin, Luxpkgs.Admin.Admin

    timestamps(type: :utc_datetime)
  end

  @trusted_avatar_hosts ~w(avatars.githubusercontent.com)

  def unique_username(%Luxpkgs.Accounts.User{} = user), do: user.username

  def bio_changeset(user, bio) do
    user
    |> Ecto.Changeset.change(%{bio: sanitize_bio(bio)})
    |> validate_length(:bio, max: 160)
  end

  def suspended?(%__MODULE__{suspended_at: nil}), do: false
  def suspended?(%__MODULE__{}), do: true

  def suspend_changeset(user, attrs) do
    user
    |> cast(attrs, [:suspension_reason])
    |> validate_required([:suspension_reason])
    |> put_change(:suspended_at, DateTime.utc_now(:second))
  end

  def unsuspend_changeset(user) do
    change(user, %{suspended_at: nil, suspension_reason: nil})
  end

  defp sanitize_bio(bio) when is_binary(bio) do
    bio |> strip_urls() |> String.trim()
  end

  defp sanitize_bio(bio), do: bio

  # FIXME: heuristic, not a parser; obfuscated links (e.g. "evil . com") still pass.
  def strip_urls(bio) when is_binary(bio) do
    String.replace(bio, ~r/(?:https?:\/\/|www\.)[^\s]+|\b[a-z0-9-]+(?:\.[a-z0-9-]+)+\S*/i, "")
  end

  def strip_urls(bio) when is_nil(bio), do: bio

  def oauth_changeset(user, %Auth{} = auth) do
    attrs = %{
      provider: to_string(auth.provider),
      # TODO: Github does this for some reason. We must test if gitlab does this too
      username: auth.info.nickname,
      aka: auth.info.name,
      avatar_url: auth.info.image
    }

    user
    |> email_changeset(%{email: auth.info.email})
    |> cast(attrs, [:provider, :username, :aka, :avatar_url])
    |> validate_required([:username])
    |> unique_constraint([:provider, :username])
    |> validate_provider()
    |> validate_avatar_url()

    # |> validate_aka()
  end

  defp validate_provider(changeset) do
    changeset
    |> validate_required(:provider)
    |> validate_inclusion(:provider, ["github", "gitlab"])
  end

  defp validate_aka(changeset) do
    changeset =
      changeset
      |> unique_constraint(:aka)
      |> validate_length(:aka, min: 1, max: 20)
      |> validate_format(:aka, ~r/^[a-zA-Z0-9_\-]+$/,
        message: "only allows letters, numbers and underscores"
      )

    username = get_field(changeset, :username)
    aka = get_field(changeset, :aka)

    if username_exists?(username) && is_nil(aka) do
      validate_required(changeset, [:aka])
    else
      changeset
    end
  end

  def validate_avatar_url(changeset) do
    case get_field(changeset, :avatar_url) do
      nil ->
        changeset

      url when is_binary(url) ->
        uri = URI.parse(url)

        if uri.scheme == "https" and uri.host in @trusted_avatar_hosts do
          changeset
        else
          add_error(changeset, :avatar_url, "must come from a trusted provider")
        end
    end
  end

  defp username_exists?(username) do
    !is_nil(Luxpkgs.Accounts.get_user_by_username(username))
  end

  def email_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_email()
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
  end

  def has_totp?(%__MODULE__{} = user) do
    Repo.exists?(from t in TotpSecret, where: t.user_id == ^user.id)
  end
end
