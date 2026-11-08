defmodule Luxpkgs.Audit.Catalog do
  @moduledoc """
  Human labels and filter groupings for audit actions.

  Keep this list in sync with every action written through Luxpkgs.Audit.
  Unknown actions still render and filter by their raw name.
  """

  @groups [
    %{
      label: "Packages and releases",
      actions: [
        %{action: "package.created", label: "created"},
        %{action: "package.updated", label: "updated"},
        %{action: "package.hidden", label: "hid"},
        %{action: "package.unhidden", label: "unhid"},
        %{action: "package.removed", label: "removed"},
        %{action: "package.restored", label: "restored"},
        %{action: "package.featured", label: "featured"},
        %{action: "package.unfeatured", label: "unfeatured"},
        %{action: "release.published", label: "published"},
        %{action: "release.yanked", label: "yanked"},
        %{action: "release.unyanked", label: "unyanked"}
      ]
    },
    %{
      label: "Reports",
      actions: [
        %{action: "report.submitted", label: "submitted a report on"},
        %{action: "report.resolved", label: "resolved a report on"},
        %{action: "report.dismissed", label: "dismissed a report on"},
        %{action: "report.warned", label: "warned about"}
      ]
    },
    %{
      label: "Users and accounts",
      actions: [
        %{action: "user.registered", label: "signed up"},
        %{action: "user.deleted", label: "deleted their account"},
        %{action: "user.suspended", label: "suspended"},
        %{action: "user.unsuspended", label: "unsuspended"},
        %{action: "user.totp_enabled", label: "enabled two-factor authentication"},
        %{action: "user.totp_disabled", label: "disabled two-factor authentication"},
        %{action: "user.backup_codes_regenerated", label: "regenerated backup codes"},
        %{action: "user.api_key_generated", label: "generated an API key"},
        %{action: "user.api_key_revoked", label: "revoked an API key"}
      ]
    },
    %{
      label: "Admin access",
      actions: [
        %{action: "admin.granted", label: "granted admin access to"},
        %{action: "admin.revoked", label: "revoked admin access from"},
        %{action: "admin.role_changed", label: "changed the admin role of"},
        %{action: "admin.totp_verified", label: "verified admin TOTP"},
        %{action: "admin.totp_failed", label: "failed admin TOTP"}
      ]
    }
  ]

  def groups, do: @groups

  def actions, do: Enum.flat_map(@groups, & &1.actions)

  def action_names, do: Enum.map(actions(), & &1.action)

  def label(action) do
    Enum.find_value(actions(), action, fn
      %{action: ^action, label: label} -> label
      _action -> nil
    end)
  end
end
