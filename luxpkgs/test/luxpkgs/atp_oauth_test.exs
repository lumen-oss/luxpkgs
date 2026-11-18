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

  test "carries the profile fields and the PDS endpoint in the auth" do
    auth =
      Luxpkgs.AtpOauth.auth("did:plc:abc123", "amartin.beer", %{
        name: "Amartin",
        image: "https://pds.example/blob",
        pds_endpoint: "https://pds.example"
      })

    assert auth.info.name == "Amartin"
    assert auth.info.image == "https://pds.example/blob"
    assert auth.extra.raw_info.pds_endpoint == "https://pds.example"
  end

  test "reads the display name and avatar from a profile record" do
    body = %{
      "value" => %{
        "displayName" => "  Amartin  ",
        "avatar" => %{"ref" => %{"$link" => "bafkreiabc"}}
      }
    }

    attrs = Luxpkgs.AtpOauth.profile_attributes("https://pds.example", "did:plc:abc123", body)

    assert attrs.name == "Amartin"

    assert attrs.image ==
             "https://pds.example/xrpc/com.atproto.sync.getBlob?did=did%3Aplc%3Aabc123&cid=bafkreiabc"
  end

  test "treats a missing or empty profile as no display fields" do
    assert Luxpkgs.AtpOauth.profile_attributes("https://pds.example", "did:plc:abc123", nil) ==
             %{}

    assert Luxpkgs.AtpOauth.profile_attributes(
             "https://pds.example",
             "did:plc:abc123",
             %{"value" => %{}}
           ) == %{name: nil, image: nil}
  end

  test "caps the display name at the aka column size" do
    attrs =
      Luxpkgs.AtpOauth.profile_attributes("https://pds.example", "did:plc:abc123", %{
        "value" => %{"displayName" => String.duplicate("a", 300)}
      })

    assert String.length(attrs.name) == 255
  end

  test "publishes client metadata with the loopback callback" do
    metadata = Luxpkgs.AtpOauth.client_metadata()

    assert metadata["scope"] == "atproto"
    assert metadata["application_type"] == "native"
    assert metadata["redirect_uris"] == ["http://127.0.0.1:4002/auth/atproto/callback"]
  end
end
