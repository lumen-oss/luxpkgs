defmodule Luxpkgs.Repo.Migrations.CreateAdminAuditEvents do
  use Ecto.Migration

  def change do
    create table(:admin_audit_events) do
      add :type, :string, null: false
      add :action, :string, null: false
      add :actor_admin_id, references(:admins, on_delete: :nilify_all)
      add :actor_label, :string, null: false
      add :target_type, :string
      add :target_id, :bigint
      add :target_label, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:admin_audit_events, [:inserted_at])
    create index(:admin_audit_events, [:actor_admin_id])
    create index(:admin_audit_events, [:target_type, :target_id])
    create index(:admin_audit_events, [:type])
  end
end
