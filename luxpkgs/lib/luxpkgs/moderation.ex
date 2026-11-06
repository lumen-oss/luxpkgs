defmodule Luxpkgs.Moderation do
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Luxpkgs.Accounts.User
  alias Luxpkgs.Admin.Admin
  alias Luxpkgs.Admin.Permissions
  alias Luxpkgs.Audit
  alias Luxpkgs.Moderation.Report
  alias Luxpkgs.Packages.Package
  alias Luxpkgs.Repo

  @doc """
  Creates an open report for an active package.

  A user can only have one open report per package.
  """
  def create_report(%User{} = user, %Package{status: :active} = package, attrs) do
    if open_report?(user, package) do
      {:error, :already_open}
    else
      %Report{}
      |> Report.changeset(
        Map.merge(public_attrs(attrs), %{
          "package_id" => package.id,
          "reporter_id" => user.id
        })
      )
      |> Repo.insert()
      |> case do
        {:ok, report} -> {:ok, report}
        {:error, changeset} -> report_error(changeset)
      end
    end
  end

  def create_report(_user, _package, _attrs), do: {:error, :inactive_package}

  def open_report?(%User{id: user_id}, %Package{id: package_id}) do
    Repo.exists?(
      from report in Report,
        where:
          report.package_id == ^package_id and report.reporter_id == ^user_id and
            report.status == :open
    )
  end

  def get_report(id) do
    Repo.get(Report, id)
    |> Repo.preload([:package, :reporter])
  end

  @doc """
  Lists reports, oldest first.
  """
  def list_reports(opts \\ []) do
    from(report in Report,
      join: package in assoc(report, :package),
      as: :package,
      order_by: [asc: report.inserted_at, asc: report.id],
      preload: [:package, :reporter]
    )
    |> filter_status(Keyword.get(opts, :status, "open"))
    |> filter_reason(Keyword.get(opts, :reason))
    |> filter_package(Keyword.get(opts, :package))
    |> filter_from(Keyword.get(opts, :from))
    |> filter_to(Keyword.get(opts, :to))
    # shortcut: the queue is capped at 100 rows, add pagination when the open queue outgrows it
    |> limit(100)
    |> Repo.all()
  end

  def resolve_report(%Admin{} = admin, %Report{} = report, note) do
    close_report(admin, report, :resolved, "report.resolved", :resolve_report, note)
  end

  def resolve_report(_admin, _report, _note), do: {:error, :insufficient_permissions}

  def dismiss_report(%Admin{} = admin, %Report{} = report, note) do
    close_report(admin, report, :dismissed, "report.dismissed", :dismiss_report, note)
  end

  def dismiss_report(_admin, _report, _note), do: {:error, :insufficient_permissions}

  @doc """
  Appends a moderation warning to the package note and keeps the report open.
  """
  def warn_report(%Admin{} = admin, %Report{id: id}, note) do
    report = Repo.get(Report, id)

    cond do
      not Permissions.can?(admin, :resolve_report) ->
        {:error, :insufficient_permissions}

      blank?(note) ->
        {:error, :note_required}

      is_nil(report) or report.status != :open ->
        {:error, :not_open}

      true ->
        admin = Repo.preload(admin, :user)
        report = Repo.preload(report, :package)
        package = report.package
        note = String.trim(note)
        warning = "Report warning: " <> note

        moderation_note =
          [package.moderation_note, warning]
          |> Enum.reject(&blank?/1)
          |> Enum.join("\n\n")

        Multi.new()
        |> Multi.update(
          :package,
          Ecto.Changeset.change(package, moderation_note: moderation_note)
        )
        |> Multi.insert(
          :audit,
          Audit.changeset(
            audit_attrs(admin, report, "report.warned", %{
              "note" => note,
              "package_id" => report.package_id
            })
          )
        )
        |> Repo.transaction()
        |> case do
          {:ok, %{package: package, audit: event}} ->
            Audit.broadcast(event)
            {:ok, package}

          {:error, _step, reason, _changes} ->
            {:error, reason}
        end
    end
  end

  def warn_report(_admin, _report, _note), do: {:error, :insufficient_permissions}

  defp close_report(admin, %Report{id: id}, status, action, permission, note) do
    report = Repo.get(Report, id)

    cond do
      not Permissions.can?(admin, permission) ->
        {:error, :insufficient_permissions}

      blank?(note) ->
        {:error, :note_required}

      is_nil(report) or report.status != :open ->
        {:error, :not_open}

      true ->
        admin = Repo.preload(admin, :user)
        report = Repo.preload(report, [:package, :reporter])
        note = String.trim(note)

        Multi.new()
        |> Multi.update(
          :report,
          Ecto.Changeset.change(report,
            status: status,
            resolution_note: note,
            resolved_by_admin_id: admin.id,
            resolved_at: DateTime.utc_now() |> DateTime.truncate(:second)
          )
        )
        |> Multi.insert(
          :audit,
          Audit.changeset(
            audit_attrs(admin, report, action, %{
              "note" => note,
              "package_id" => report.package_id
            })
          )
        )
        |> Repo.transaction()
        |> case do
          {:ok, %{report: report, audit: event}} ->
            Audit.broadcast(event)
            {:ok, report}

          {:error, _step, reason, _changes} ->
            {:error, reason}
        end
    end
  end

  defp audit_attrs(admin, report, action, metadata) do
    %{
      type: :report,
      action: action,
      actor_admin_id: admin.id,
      actor_label: admin.user.username || admin.user.email,
      target_type: "report",
      target_id: report.id,
      target_label: report.package.name,
      metadata: metadata
    }
  end

  defp report_error(%Ecto.Changeset{errors: errors} = changeset) do
    case errors[:package_id] do
      {_message, options} ->
        if Keyword.get(options, :constraint_name) == "package_reports_open_unique" do
          {:error, :already_open}
        else
          {:error, changeset}
        end

      _ ->
        {:error, changeset}
    end
  end

  defp public_attrs(attrs) do
    details = attrs["details"] || attrs[:details]

    %{
      "reason" => attrs["reason"] || attrs[:reason],
      "details" => if(blank?(details), do: nil, else: details)
    }
  end

  defp filter_status(query, status) when status in [:open, :resolved, :dismissed] do
    where(query, [report], report.status == ^status)
  end

  defp filter_status(query, status) when is_binary(status) do
    case Enum.find(Report.statuses(), &(Atom.to_string(&1) == status)) do
      nil -> query
      status -> filter_status(query, status)
    end
  end

  defp filter_status(query, _status), do: query

  defp filter_reason(query, reason)
       when reason in [:malicious, :spam, :copyright, :broken, :other] do
    where(query, [report], report.reason == ^reason)
  end

  defp filter_reason(query, reason) when is_binary(reason) do
    case Enum.find(Report.reasons(), &(Atom.to_string(&1) == reason)) do
      nil -> query
      reason -> filter_reason(query, reason)
    end
  end

  defp filter_reason(query, _reason), do: query

  defp filter_package(query, name) when is_binary(name) and name != "" do
    where(query, [_report, package], ilike(package.name, ^"%#{name}%"))
  end

  defp filter_package(query, _package), do: query

  defp filter_from(query, %Date{} = from) do
    where(query, [report], report.inserted_at >= ^NaiveDateTime.new!(from, ~T[00:00:00]))
  end

  defp filter_from(query, _from), do: query

  defp filter_to(query, %Date{} = to) do
    where(
      query,
      [report],
      report.inserted_at < ^NaiveDateTime.new!(Date.add(to, 1), ~T[00:00:00])
    )
  end

  defp filter_to(query, _to), do: query

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
end
