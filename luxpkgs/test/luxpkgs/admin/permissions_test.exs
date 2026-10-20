defmodule Luxpkgs.Admin.PermissionsTest do
  use ExUnit.Case, async: true

  alias Luxpkgs.Admin.Admin
  alias Luxpkgs.Admin.Permissions

  test "admins can do moderator and admin actions" do
    admin = %Admin{active: true, role: :admin}

    assert Permissions.can?(admin, :view_dashboard)
    assert Permissions.can?(admin, :hide_package)
    assert Permissions.can?(admin, :remove_package)
    assert Permissions.can?(admin, :suspend_user)
    assert Permissions.can?(admin, :view_audit)
  end

  test "moderators can moderate packages and reports" do
    moderator = %Admin{active: true, role: :moderator}

    assert Permissions.can?(moderator, :view_dashboard)
    assert Permissions.can?(moderator, :hide_package)
    assert Permissions.can?(moderator, :resolve_report)
  end

  test "moderators cannot perform admin-only actions" do
    moderator = %Admin{active: true, role: :moderator}

    refute Permissions.can?(moderator, :remove_package)
    refute Permissions.can?(moderator, :suspend_user)
    refute Permissions.can?(moderator, :transfer_ownership)
    refute Permissions.can?(moderator, :view_audit)
  end

  test "inactive admins have no permissions" do
    admin = %Admin{active: false, role: :admin}

    refute Permissions.can?(admin, :view_dashboard)
    refute Permissions.can?(admin, :view_audit)
  end

  test "unknown roles and permissions are denied" do
    refute Permissions.can?(:owner, :view_dashboard)
    refute Permissions.can?(%Admin{active: true, role: :admin}, :become_owner)
  end
end
