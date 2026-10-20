defmodule Luxpkgs.Admin.Permissions do
  alias Luxpkgs.Admin.Admin

  @moderator_permissions [
    :view_dashboard,
    :view_packages,
    :view_package,
    :hide_package,
    :unhide_package,
    :view_reports,
    :resolve_report,
    :dismiss_report,
    :view_stats
  ]

  @admin_permissions @moderator_permissions ++
                       [
                         :remove_package,
                         :restore_package,
                         :feature_package,
                         :view_users,
                         :suspend_user,
                         :unsuspend_user,
                         :transfer_ownership,
                         :view_audit
                       ]

  @permissions %{
    moderator: @moderator_permissions,
    admin: @admin_permissions
  }

  def can?(%Admin{active: true, role: role}, permission), do: can?(role, permission)
  def can?(%Admin{}, _permission), do: false

  def can?(role, permission) when role in [:admin, :moderator] do
    permission in Map.fetch!(@permissions, role)
  end

  def can?(_role, _permission), do: false

  def permissions(role) when role in [:admin, :moderator], do: Map.fetch!(@permissions, role)
  def permissions(_role), do: []
end
