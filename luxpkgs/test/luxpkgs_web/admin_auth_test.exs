defmodule LuxpkgsWeb.AdminAuthTest do
  use ExUnit.Case, async: true

  alias LuxpkgsWeb.AdminAuth

  test "page_fresh?/1 accepts a recent verification" do
    now = System.os_time(:second)

    assert AdminAuth.page_fresh?(now)
    assert AdminAuth.page_fresh?(now - 29 * 60)
  end

  test "page_fresh?/1 rejects stale, future, and missing timestamps" do
    now = System.os_time(:second)

    refute AdminAuth.page_fresh?(now - 31 * 60)
    refute AdminAuth.page_fresh?(now + 60)
    refute AdminAuth.page_fresh?(nil)
    refute AdminAuth.page_fresh?("123")
  end

  test "destructive_fresh?/1 uses the 10 minute window" do
    now = System.os_time(:second)

    assert AdminAuth.destructive_fresh?(%{assigns: %{admin_totp_verified_at: now - 9 * 60}})
    refute AdminAuth.destructive_fresh?(%{assigns: %{admin_totp_verified_at: now - 11 * 60}})
    refute AdminAuth.destructive_fresh?(%{assigns: %{}})
  end
end
