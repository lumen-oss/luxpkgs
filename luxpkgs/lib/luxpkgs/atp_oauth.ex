defmodule Luxpkgs.AtpOauth do
  @moduledoc """
  The atproto OAuth flow, wrapping the Latch client.

  Everything that talks to Latch goes through here so the rest of the app
  works with the same `Ueberauth.Auth` shape as the GitHub login.
  """

  @client Luxpkgs.AtpOauth.Client

  def configured? do
    not is_nil(Application.get_env(:luxpkgs, :atproto))
  end

  def client_metadata do
    Latch.client_metadata(@client)
  end

  def authorize(handle) do
    case normalize_handle(handle) do
      "" -> {:error, :invalid_handle}
      handle -> Latch.authorize(@client, handle)
    end
  end

  def callback(params) do
    with {:ok, %{did: did, handle: handle, pds_endpoint: pds_endpoint}} <-
           Latch.callback(@client, params) do
      attrs =
        pds_endpoint
        |> profile_attributes(did, fetch_record(pds_endpoint, did))
        |> Map.put(:pds_endpoint, pds_endpoint)

      {:ok, auth(did, handle, attrs)}
    end
  end

  def auth(did, handle), do: auth(did, handle, %{})

  def auth(did, handle, attrs) do
    %Ueberauth.Auth{
      provider: :atproto,
      uid: did,
      info: %Ueberauth.Auth.Info{
        nickname: handle,
        name: attrs[:name],
        email: nil,
        image: attrs[:image]
      },
      extra: %Ueberauth.Auth.Extra{raw_info: %{pds_endpoint: attrs[:pds_endpoint]}}
    }
  end

  def normalize_handle(handle) when is_binary(handle) do
    handle |> String.trim() |> String.trim_leading("@") |> String.trim()
  end

  def normalize_handle(_handle), do: ""

  @doc """
  Maps a profile record body to the display fields carried by the auth struct.
  """
  def profile_attributes(pds_endpoint, did, %{"value" => value}) when is_map(value) do
    %{name: display_name(value), image: avatar_url(pds_endpoint, did, value)}
  end

  def profile_attributes(_pds_endpoint, _did, _body), do: %{}

  defp fetch_record(pds_endpoint, did) do
    case Req.get(profile_url(pds_endpoint, did), receive_timeout: 2_000, retry: false) do
      {:ok, %Req.Response{status: 200, body: body}} -> body
      _ -> nil
    end
  rescue
    # Best effort: a broken or slow PDS must not block the login.
    _ -> nil
  end

  defp profile_url(pds_endpoint, did) do
    pds_endpoint <>
      "/xrpc/com.atproto.repo.getRecord?" <>
      URI.encode_query(repo: did, collection: "app.bsky.actor.profile", rkey: "self")
  end

  defp avatar_url(pds_endpoint, did, %{"avatar" => %{"ref" => %{"$link" => cid}}})
       when is_binary(cid) do
    pds_endpoint <> "/xrpc/com.atproto.sync.getBlob?" <> URI.encode_query(did: did, cid: cid)
  end

  defp avatar_url(_pds_endpoint, _did, _value), do: nil

  # users.aka is varchar(255), while atproto allows 640 graphemes.
  defp display_name(%{"displayName" => name}) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      name -> String.slice(name, 0, 255)
    end
  end

  defp display_name(_value), do: nil
end
