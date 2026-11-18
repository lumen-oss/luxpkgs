defmodule LuxpkgsWeb.UserLive.SettingsTest do
  use LuxpkgsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Luxpkgs.AccountsFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/settings")

      assert html =~ "Settings"
      assert html =~ "Manage your profile and account preferences"
    end

    test "updates the user's bio", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/settings")

      lv
      |> form("#bio_form", user: %{bio: "Building rocks"})
      |> render_submit()

      assert Luxpkgs.Accounts.get_user!(user.id).bio == "Building rocks"
    end

    test "renders a bio character counter", %{conn: conn} do
      user = user_fixture()

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/settings")

      assert html =~ "0/160"
      assert html =~ ~s(phx-hook="CharacterCounter")
      assert html =~ ~s(data-counter-target="bio-count")
    end

    test "strips links from the submitted bio", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/settings")

      lv
      |> form("#bio_form", user: %{bio: "Visit https://evil.example and evil.com"})
      |> render_submit()

      bio = Luxpkgs.Accounts.get_user!(user.id).bio

      refute bio =~ "https://evil.example"
      refute bio =~ "evil.com"
    end

    test "shows linked accounts and the providers left to link", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/settings")

      assert html =~ "Linked accounts"
      assert html =~ "GitHub"
      assert html =~ user.username
      assert has_element?(lv, "#link-atproto-form")
      refute html =~ "Connect GitHub"
    end

    test "hides the connect form of an already linked provider", %{conn: conn} do
      user = user_fixture()

      {:ok, :linked} =
        Luxpkgs.Accounts.link_identity(
          user,
          Luxpkgs.AtpOauth.auth("did:plc:settings1", "settings.bsky.social")
        )

      {:ok, lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/settings")

      assert html =~ "AT Protocol"
      assert html =~ "settings.bsky.social"
      refute has_element?(lv, "#link-atproto-form")
    end

    test "disables unlinking the only identity", %{conn: conn} do
      {:ok, lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/settings")

      refute html =~ "Avatar source"
      assert has_element?(lv, "button[disabled]", "Unlink")
    end

    test "switches the avatar source once two identities are linked", %{conn: conn} do
      user = user_fixture()

      github = %Ueberauth.Auth{
        provider: :github,
        info: %Ueberauth.Auth.Info{
          nickname: user.username,
          name: user.aka,
          email: user.email,
          image: "https://avatars.githubusercontent.com/u/4242"
        }
      }

      assert :ok = Luxpkgs.Accounts.sync_profile(user, github)
      user = Luxpkgs.Accounts.get_user!(user.id)

      assert {:ok, :linked} =
               Luxpkgs.Accounts.link_identity(
                 user,
                 Luxpkgs.AtpOauth.auth("did:plc:settings2", "avatar.bsky.social")
               )

      {:ok, lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/settings")

      assert html =~ "Avatar source"
      assert has_element?(lv, "#unlink_atproto_form")
      refute has_element?(lv, "button[disabled]", "Unlink")

      html =
        lv
        |> element("#avatar-source-form")
        |> render_change(%{"provider" => "atproto"})

      assert html =~ "Avatar source updated."
      assert html =~ "No picture on AT Protocol, so your profile shows your initial."

      user = Luxpkgs.Accounts.get_user!(user.id)
      assert user.avatar_source == "atproto"
      assert user.avatar_url == nil

      html =
        lv
        |> element("#avatar-source-form")
        |> render_change(%{"provider" => "github"})

      assert html =~ "Showing the picture from GitHub."

      assert Luxpkgs.Accounts.get_user!(user.id).avatar_source == "github"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/login"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "redirects if user is not in sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(~p"/settings")
        |> follow_redirect(conn, ~p"/login")

      assert conn.resp_body =~ "You must re-authenticate to access this page."
    end
  end

  describe "delete account" do
    test "deletes the account and redirects home", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/settings")

      lv
      |> form("#delete_account_form", confirm: user.username)
      |> render_submit()

      assert_redirect(lv, ~p"/")
      refute Luxpkgs.Accounts.get_user(user.id)
    end

    test "rejects a mismatched confirmation", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/settings")

      html =
        lv
        |> form("#delete_account_form", confirm: "not-the-username")
        |> render_submit()

      assert html =~ "Username does not match. Your account was not deleted."
      assert Luxpkgs.Accounts.get_user(user.id)
    end
  end
end
