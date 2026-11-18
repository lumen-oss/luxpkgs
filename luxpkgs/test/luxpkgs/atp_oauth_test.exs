defmodule Luxpkgs.AtpOauthTest do
  use ExUnit.Case, async: true

  test "the Latch client and its store are supervised" do
    assert Process.whereis(Luxpkgs.AtpOauth.Client)
    assert Process.whereis(Luxpkgs.AtpOauthStore)
    assert :ets.whereis(Luxpkgs.AtpOauthStore_requests) != :undefined
  end

  test "normalizes handles" do
    assert Luxpkgs.AtpOauth.normalize_handle("  @amartin.beer ") == "amartin.beer"
    assert Luxpkgs.AtpOauth.normalize_handle(nil) == ""
  end

  test "rejects an empty handle without calling the network" do
    assert Luxpkgs.AtpOauth.authorize("   ") == {:error, :invalid_handle}
  end

  test "builds an auth struct from the DID and handle" do
    auth = Luxpkgs.AtpOauth.auth("did:plc:abc123", "amartin.beer")

    assert auth.provider == :atproto
    assert auth.uid == "did:plc:abc123"
    assert auth.info.nickname == "amartin.beer"
    assert auth.info.email == nil
  end

  test "publishes client metadata with the loopback callback" do
    metadata = Luxpkgs.AtpOauth.client_metadata()

    assert metadata["scope"] == "atproto"
    assert metadata["application_type"] == "native"
    assert metadata["redirect_uris"] == ["http://127.0.0.1:4002/auth/atproto/callback"]
  end
end
