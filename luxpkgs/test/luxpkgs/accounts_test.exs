defmodule Luxpkgs.AccountsTest do
  use Luxpkgs.DataCase

  alias Luxpkgs.Accounts
  alias Luxpkgs.Repo

  import Luxpkgs.AccountsFixtures
  import Luxpkgs.AdminFixtures
  alias Luxpkgs.Accounts.{User, UserIdentity, UserToken}
  alias Luxpkgs.Admin
  alias Luxpkgs.Admin.Admin, as: AdminRow
  alias Luxpkgs.Audit

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "get_user_by_auth/1" do
    test "matches a user from the same provider by email" do
      user = user_fixture(%{email: "same-provider@example.com"})

      auth = %Ueberauth.Auth{
        provider: "github",
        info: %Ueberauth.Auth.Info{nickname: "renamed_on_github", email: user.email}
      }

      assert %User{id: id} = Accounts.get_user_by_auth(auth)
      assert id == user.id
    end

    test "does not match a user from another provider by email" do
      user = user_fixture(%{email: "shared@example.com"})

      user =
        user
        |> Ecto.Changeset.change(provider: "gitlab")
        |> Luxpkgs.Repo.update!()

      auth = %Ueberauth.Auth{
        provider: "github",
        info: %Ueberauth.Auth.Info{nickname: "someone_else", email: user.email}
      }

      refute Accounts.get_user_by_auth(auth)
    end

    test "matches the identity by uid when the handle changed" do
      user = user_fixture()
      identity = Repo.get_by!(UserIdentity, user_id: user.id)
      Repo.update!(Ecto.Changeset.change(identity, uid: "42"))

      auth = %Ueberauth.Auth{
        provider: "github",
        uid: "42",
        info: %Ueberauth.Auth.Info{nickname: "renamed_on_github", email: user.email}
      }

      assert %User{id: id} = Accounts.get_user_by_auth(auth)
      assert id == user.id
    end

    test "does not match a claimed handle with a different uid" do
      user = user_fixture()
      identity = Repo.get_by!(UserIdentity, user_id: user.id)
      Repo.update!(Ecto.Changeset.change(identity, uid: "original"))

      auth = %Ueberauth.Auth{
        provider: "github",
        uid: "reclaimed",
        info: %Ueberauth.Auth.Info{nickname: identity.username}
      }

      refute Accounts.get_user_by_auth(auth)
    end

    test "stores the uid on a backfilled identity matched by username" do
      user = user_fixture()
      identity = Repo.get_by!(UserIdentity, user_id: user.id)

      auth = %Ueberauth.Auth{
        provider: "github",
        uid: "67890",
        info: %Ueberauth.Auth.Info{nickname: identity.username}
      }

      assert %User{id: id} = Accounts.get_user_by_auth(auth)
      assert id == user.id
      assert Repo.get!(UserIdentity, identity.id).uid == "67890"
    end
  end

  describe "register_user/1" do
    test "stores the oauth avatar URL" do
      auth = %Ueberauth.Auth{
        provider: "github",
        info: %Ueberauth.Auth.Info{
          nickname: "ntb",
          name: "NTBBloodbath",
          email: unique_user_email(),
          image: "https://avatars.githubusercontent.com/u/36456999"
        }
      }

      assert {:ok, %User{avatar_url: url}} = Accounts.register_user(auth)
      assert url == "https://avatars.githubusercontent.com/u/36456999"
    end

    test "stores the DID and handle of an atproto account" do
      auth = %Ueberauth.Auth{
        provider: :atproto,
        uid: "did:plc:atproto123",
        info: %Ueberauth.Auth.Info{
          nickname: "someone.bsky.social",
          email: unique_user_email()
        }
      }

      assert {:ok, %User{provider: "atproto", username: "someone.bsky.social"} = user} =
               Accounts.register_user(auth)

      identity = Repo.get_by(UserIdentity, user_id: user.id, provider: "atproto")
      assert identity.uid == "did:plc:atproto123"
      assert identity.username == "someone.bsky.social"
    end

    test "stores an atproto avatar from the user's PDS" do
      avatar =
        "https://pds.example/xrpc/com.atproto.sync.getBlob?did=did%3Aplc%3Aatproto123&cid=bafkrei"

      auth = %Ueberauth.Auth{
        provider: :atproto,
        uid: "did:plc:atproto123",
        info: %Ueberauth.Auth.Info{
          nickname: "someone.bsky.social",
          email: unique_user_email(),
          image: avatar
        },
        extra: %Ueberauth.Auth.Extra{raw_info: %{pds_endpoint: "https://pds.example"}}
      }

      assert {:ok, %User{avatar_url: ^avatar}} = Accounts.register_user(auth)
    end

    test "rejects avatar URLs from untrusted hosts" do
      auth = %Ueberauth.Auth{
        provider: "github",
        info: %Ueberauth.Auth.Info{
          nickname: "ntb",
          name: "NTBBloodbath",
          email: unique_user_email(),
          image: "https://evil.example/avatar.png"
        }
      }

      assert {:error, %Ecto.Changeset{errors: errors}} = Accounts.register_user(auth)
      assert {"must come from a trusted provider", _opts} = errors[:avatar_url]
    end

    test "returns an error when the email belongs to another account" do
      existing = user_fixture()

      auth = %Ueberauth.Auth{
        provider: "github",
        info: %Ueberauth.Auth.Info{
          nickname: "email_taken",
          name: "Email Taken",
          email: existing.email,
          image: nil
        }
      }

      assert {:error, %Ecto.Changeset{errors: errors}} = Accounts.register_user(auth)
      assert {"has already been taken", _opts} = errors[:email]
    end

    test "creates the first identity next to the user" do
      auth = %Ueberauth.Auth{
        provider: "github",
        uid: "424242",
        info: %Ueberauth.Auth.Info{
          nickname: "new_identity",
          name: "New Identity",
          email: unique_user_email(),
          image: "https://avatars.githubusercontent.com/u/424242"
        }
      }

      assert {:ok, %User{id: user_id}} = Accounts.register_user(auth)

      identity = Repo.get_by!(UserIdentity, user_id: user_id)
      assert identity.provider == "github"
      assert identity.uid == "424242"
      assert identity.username == "new_identity"
      assert identity.aka == "New Identity"
      assert identity.avatar_url == "https://avatars.githubusercontent.com/u/424242"
    end
  end

  describe "sync_profile/2" do
    test "updates the identity and the primary display copy" do
      user = user_fixture()

      auth = %Ueberauth.Auth{
        provider: "github",
        uid: "777",
        info: %Ueberauth.Auth.Info{
          nickname: "fresh_handle",
          name: "Fresh Name",
          email: user.email,
          image: "https://avatars.githubusercontent.com/u/777"
        }
      }

      assert :ok = Accounts.sync_profile(user, auth)

      identity = Repo.get_by!(UserIdentity, user_id: user.id)
      assert identity.uid == "777"
      assert identity.username == "fresh_handle"

      user = Repo.get!(User, user.id)
      assert user.username == "fresh_handle"
      assert user.aka == "Fresh Name"
      assert user.avatar_url == "https://avatars.githubusercontent.com/u/777"
    end

    test "never replaces a stored uid" do
      user = user_fixture()
      identity = Repo.get_by!(UserIdentity, user_id: user.id)
      Repo.update!(Ecto.Changeset.change(identity, uid: "original"))

      auth = %Ueberauth.Auth{
        provider: "github",
        uid: "different",
        info: %Ueberauth.Auth.Info{nickname: identity.username, email: user.email}
      }

      assert :ok = Accounts.sync_profile(user, auth)
      assert Repo.get!(UserIdentity, identity.id).uid == "original"
    end

    test "stores the PDS avatar of an atproto identity" do
      avatar =
        "https://pds.example/xrpc/com.atproto.sync.getBlob?did=did%3Aplc%3Aatproto123&cid=bafkrei"

      signup = %Ueberauth.Auth{
        provider: :atproto,
        uid: "did:plc:atproto123",
        info: %Ueberauth.Auth.Info{nickname: "amartin.beer", email: unique_user_email()}
      }

      assert {:ok, user} = Accounts.register_user(signup)

      auth = %Ueberauth.Auth{
        provider: :atproto,
        uid: "did:plc:atproto123",
        info: %Ueberauth.Auth.Info{
          nickname: "amartin.beer",
          name: "Amartin",
          image: avatar
        },
        extra: %Ueberauth.Auth.Extra{raw_info: %{pds_endpoint: "https://pds.example"}}
      }

      assert :ok = Accounts.sync_profile(user, auth)

      identity = Repo.get_by!(UserIdentity, user_id: user.id, provider: "atproto")
      assert identity.aka == "Amartin"
      assert identity.avatar_url == avatar
      assert Repo.get!(User, user.id).avatar_url == avatar
    end

    test "does not trust an avatar outside the user's PDS" do
      signup = %Ueberauth.Auth{
        provider: :atproto,
        uid: "did:plc:atproto123",
        info: %Ueberauth.Auth.Info{nickname: "amartin.beer", email: unique_user_email()}
      }

      assert {:ok, user} = Accounts.register_user(signup)

      auth = %Ueberauth.Auth{
        provider: :atproto,
        uid: "did:plc:atproto123",
        info: %Ueberauth.Auth.Info{
          nickname: "amartin.beer",
          image: "https://evil.example/avatar.png"
        },
        extra: %Ueberauth.Auth.Extra{raw_info: %{pds_endpoint: "https://pds.example"}}
      }

      assert :ok = Accounts.sync_profile(user, auth)

      identity = Repo.get_by!(UserIdentity, user_id: user.id, provider: "atproto")
      assert is_nil(identity.avatar_url)
    end
  end

  describe "link_identity/2" do
    test "links an identity from another provider" do
      user = user_fixture()

      assert {:ok, :linked} =
               Accounts.link_identity(user, atproto_auth("did:plc:linked1", "linked.bsky.social"))

      identity = Repo.get_by!(UserIdentity, user_id: user.id, provider: "atproto")
      assert identity.uid == "did:plc:linked1"
      assert identity.username == "linked.bsky.social"
    end

    test "refuses an identity that belongs to another user" do
      owner = user_fixture()
      user = user_fixture()
      auth = atproto_auth("did:plc:owned1", "owned.bsky.social")

      assert {:ok, :linked} = Accounts.link_identity(owner, auth)
      assert {:error, :taken} = Accounts.link_identity(user, auth)
      refute Repo.get_by(UserIdentity, user_id: user.id, provider: "atproto")
    end

    test "reports an identity already linked to the same user" do
      user = user_fixture()
      auth = atproto_auth("did:plc:again1", "again.bsky.social")

      assert {:ok, :linked} = Accounts.link_identity(user, auth)
      assert {:ok, :already_linked} = Accounts.link_identity(user, auth)

      identities =
        Repo.all(
          from i in UserIdentity,
            where: i.user_id == ^user.id and i.provider == "atproto"
        )

      assert length(identities) == 1
    end

    test "refuses a second account of an already linked provider" do
      user = user_fixture()

      auth = %Ueberauth.Auth{
        provider: :github,
        uid: "9999",
        info: %Ueberauth.Auth.Info{nickname: "other_handle", email: nil}
      }

      assert {:error, :different_identity} = Accounts.link_identity(user, auth)
    end

    defp atproto_auth(uid, handle) do
      %Ueberauth.Auth{
        provider: :atproto,
        uid: uid,
        info: %Ueberauth.Auth.Info{nickname: handle, email: nil}
      }
    end
  end

  describe "update_bio/2" do
    test "updates the user's bio" do
      user = user_fixture()

      assert {:ok, %User{bio: "Making awesome Lua plugins"}} =
               Accounts.update_bio(user, "Making awesome Lua plugins")
    end

    test "strips URLs from the bio" do
      user = user_fixture()

      assert {:ok, %User{bio: bio}} =
               Accounts.update_bio(user, "Check my site: https://malicious.example/foo")

      refute bio =~ "https://"
    end

    test "strips bare domains from the bio" do
      user = user_fixture()

      assert {:ok, %User{bio: bio}} = Accounts.update_bio(user, "Visit evil.com now")

      refute bio =~ "evil.com"
    end

    test "trims surrounding whitespace from the bio" do
      user = user_fixture()

      assert {:ok, %User{bio: "hello world"}} =
               Accounts.update_bio(user, "  hello world\n")
    end

    test "rejects bios longer than 160 characters" do
      user = user_fixture()

      assert {:error, %Ecto.Changeset{errors: errors}} =
               Accounts.update_bio(user, String.duplicate("a", 161))

      assert {"should be at most %{count} character(s)", _opts} = errors[:bio]
    end
  end

  describe "update_user_avatar/2" do
    test "updates the avatar URL" do
      user = user_fixture()

      assert {:ok, %User{avatar_url: "https://avatars.githubusercontent.com/u/36456999"}} =
               Accounts.update_user_avatar(
                 user,
                 "https://avatars.githubusercontent.com/u/36456999"
               )
    end

    test "rejects avatar URLs from untrusted hosts" do
      user = user_fixture()

      assert {:error, %Ecto.Changeset{errors: errors}} =
               Accounts.update_user_avatar(user, "https://evil.example/avatar.png")

      assert {"must come from a trusted provider", _opts} = errors[:avatar_url]
    end

    test "rejects non-https avatar URLs" do
      user = user_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Accounts.update_user_avatar(
                 user,
                 "http://avatars.githubusercontent.com/u/76052559"
               )
    end
  end

  describe "delete_user/1" do
    import Luxpkgs.PackagesFixtures

    alias Luxpkgs.Accounts.{TOTP, TotpBackupCode, TotpSecret}

    test "deletes the user and their session tokens" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert {:ok, [%UserToken{token: ^token}]} = Accounts.delete_user(user)
      refute Accounts.get_user(user.id)
      refute Repo.get_by(UserToken, token: token)
    end

    test "removes two-factor authentication data" do
      user = user_fixture()
      :ok = TOTP.enable(user)
      _codes = TOTP.generate_backup_codes(user)

      assert {:ok, _tokens} = Accounts.delete_user(user)

      refute Repo.exists?(from t in TotpSecret, where: t.user_id == ^user.id)
      refute Repo.exists?(from c in TotpBackupCode, where: c.user_id == ^user.id)
    end

    test "reassigns packages to the deleted user without deleting releases" do
      user = user_fixture()
      scope = Luxpkgs.Accounts.Scope.for_user(user)
      package = package_fixture(scope)
      release = release_fixture(scope, package)

      assert {:ok, _tokens} = Accounts.delete_user(user)

      assert %{user_id: owner_id} = Repo.get!(Luxpkgs.Packages.Package, package.id)
      assert owner_id == Accounts.deleted_user().id
      assert Repo.get!(Luxpkgs.Packages.Release, release.id).package_id == package.id
    end

    test "the deleted user is created only once" do
      assert Accounts.deleted_user().id == Accounts.deleted_user().id
    end
  end

  describe "suspend_user/3" do
    test "sets the suspension fields" do
      actor = admin_fixture(%{role: :admin})
      user = user_fixture()

      assert {:ok, suspended, []} = Accounts.suspend_user(actor, user, "Spam")

      assert suspended.suspended_at
      assert suspended.suspension_reason == "Spam"
      assert Accounts.get_user(user.id).suspension_reason == "Spam"
    end

    test "requires a reason" do
      actor = admin_fixture(%{role: :admin})
      user = user_fixture()

      assert {:error, %Ecto.Changeset{errors: errors}} =
               Accounts.suspend_user(actor, user, "")

      assert errors[:suspension_reason]
      refute Accounts.get_user(user.id).suspended_at
    end

    test "revokes session tokens and returns them" do
      actor = admin_fixture(%{role: :admin})
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert {:ok, _suspended, [%UserToken{token: ^token}]} =
               Accounts.suspend_user(actor, user, "Spam")

      refute Accounts.get_user_by_session_token(token)
      refute Repo.get_by(UserToken, token: token)
    end

    test "deactivates the user's admin row" do
      actor = admin_fixture(%{role: :admin})
      user = user_fixture()
      _admin = admin_fixture(%{user: user, role: :admin})

      assert {:ok, _suspended, _tokens} = Accounts.suspend_user(actor, user, "Spam")
      refute Repo.get_by(AdminRow, user_id: user.id).active
    end

    test "writes an audit event" do
      actor = admin_fixture(%{role: :admin})
      user = user_fixture()

      assert {:ok, _suspended, _tokens} = Accounts.suspend_user(actor, user, "Spam")

      assert [event] = Audit.list_events(action: "user.suspended", target_type: "user")

      assert event.actor_admin_id == actor.id
      assert event.target_id == user.id
      assert event.metadata["reason"] == "Spam"
    end

    test "returns tokens that disconnect live sockets" do
      actor = admin_fixture(%{role: :admin})
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      topic = "users_sessions:#{Base.url_encode64(token)}"
      LuxpkgsWeb.Endpoint.subscribe(topic)

      assert {:ok, _suspended, tokens} = Accounts.suspend_user(actor, user, "Spam")
      LuxpkgsWeb.UserAuth.disconnect_sessions(tokens)

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^topic}
    end

    test "rejects suspending yourself" do
      actor = admin_fixture(%{role: :admin})

      assert {:error, :self_suspend} =
               Accounts.suspend_user(actor, Accounts.get_user(actor.user_id), "Spam")
    end

    test "rejects suspending the last active admin" do
      actor = admin_fixture(%{role: :admin, active: false})
      user = user_fixture()
      _admin = admin_fixture(%{user: user, role: :admin})
      _moderator = admin_fixture(%{role: :moderator})

      assert Admin.active_admin_count() == 1
      assert {:error, :last_admin} = Accounts.suspend_user(actor, user, "Spam")
    end

    test "allows suspending one of several active admins" do
      actor = admin_fixture(%{role: :admin})
      user = user_fixture()
      _admin = admin_fixture(%{user: user, role: :admin})

      assert {:ok, _suspended, _tokens} = Accounts.suspend_user(actor, user, "Spam")
    end
  end

  describe "unsuspend_user/2" do
    test "clears the suspension fields" do
      actor = admin_fixture(%{role: :admin})
      user = user_fixture()
      {:ok, suspended, _tokens} = Accounts.suspend_user(actor, user, "Spam")

      assert {:ok, unsuspended} = Accounts.unsuspend_user(actor, suspended)
      assert is_nil(unsuspended.suspended_at)
      assert is_nil(unsuspended.suspension_reason)
    end

    test "keeps the admin row inactive" do
      actor = admin_fixture(%{role: :admin})
      user = user_fixture()
      _admin = admin_fixture(%{user: user, role: :admin})
      {:ok, suspended, _tokens} = Accounts.suspend_user(actor, user, "Spam")

      assert {:ok, _unsuspended} = Accounts.unsuspend_user(actor, suspended)
      refute Repo.get_by(AdminRow, user_id: user.id).active
    end

    test "writes an audit event" do
      actor = admin_fixture(%{role: :admin})
      user = user_fixture()
      {:ok, suspended, _tokens} = Accounts.suspend_user(actor, user, "Spam")

      assert {:ok, _unsuspended} = Accounts.unsuspend_user(actor, suspended)
      assert [event] = Audit.list_events(action: "user.unsuspended")
      assert event.target_id == user.id
    end
  end

  describe "get_admin_for_user/1" do
    test "returns inactive admin rows" do
      user = user_fixture()
      admin = admin_fixture(%{user: user, role: :admin, active: false})

      assert %{id: id, active: false} = Admin.get_admin_for_user(user)
      assert id == admin.id
    end
  end
end
