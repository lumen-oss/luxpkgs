defmodule Luxpkgs.Moderation.Report do
  use Ecto.Schema
  import Ecto.Changeset

  @reasons [:malicious, :spam, :copyright, :broken, :other]
  @statuses [:open, :resolved, :dismissed]

  schema "package_reports" do
    field :reason, Ecto.Enum, values: @reasons
    field :details, :string
    field :status, Ecto.Enum, values: @statuses, default: :open
    field :resolution_note, :string
    field :resolved_at, :utc_datetime

    belongs_to :package, Luxpkgs.Packages.Package
    belongs_to :reporter, Luxpkgs.Accounts.User
    belongs_to :resolved_by_admin, Luxpkgs.Admin.Admin

    timestamps(type: :utc_datetime)
  end

  def reasons, do: @reasons
  def statuses, do: @statuses

  @doc false
  def changeset(report, attrs) do
    report
    |> cast(attrs, [:package_id, :reporter_id, :reason, :details])
    |> validate_required([:package_id, :reason])
    |> validate_length(:details, max: 2000)
    |> foreign_key_constraint(:package_id)
    |> foreign_key_constraint(:reporter_id)
    |> unique_constraint([:package_id, :reporter_id],
      name: :package_reports_open_unique,
      message: "already has an open report"
    )
    |> check_constraint(:reason, name: :package_reports_reason_must_be_valid)
  end
end
