defmodule Luxpkgs.Packages.Package do
  alias Luxpkgs.Accounts.Scope
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Flop.Schema,
           filterable: [:name, :summary, :search, :user_id],
           sortable: [:name, :inserted_at],
           default_order: %{
             order_by: [:inserted_at],
             order_directions: [:desc]
           },
           default_limit: 12,
           max_limit: 50,
           adapter_opts: [
             compound_fields: [search: [:name, :summary]]
           ]}

  schema "packages" do
    field :name, :string
    field :summary, :string
    field :description, :string
    belongs_to :user, Luxpkgs.Accounts.User
    has_many :releases, Luxpkgs.Packages.Release

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(package, attrs, %Scope{} = user_scope) do
    package
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\.\-]+$/)
    # Recast here to prevent the user from changing the package name
    |> cast(attrs, [:summary, :description])
    |> validate_length(:name, min: 1, max: 20)
    |> validate_length(:summary, min: 1, max: 100)
    |> validate_length(:description, max: 9999)
    |> put_change(:user_id, user_scope.user.id)
  end
end
