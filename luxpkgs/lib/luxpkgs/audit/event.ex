defmodule Luxpkgs.Audit.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @types [:package, :report, :user, :auth, :system]

  schema "admin_audit_events" do
    field :type, Ecto.Enum, values: @types
    field :action, :string
    field :actor_label, :string
    field :target_type, :string
    field :target_id, :integer
    field :target_label, :string
    field :metadata, :map, default: %{}

    belongs_to :actor_admin, Luxpkgs.Admin.Admin, foreign_key: :actor_admin_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def types, do: @types

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :type,
      :action,
      :actor_admin_id,
      :actor_label,
      :target_type,
      :target_id,
      :target_label,
      :metadata
    ])
    |> validate_required([:type, :action, :actor_label])
    |> foreign_key_constraint(:actor_admin_id)
  end
end
