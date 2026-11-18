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
    with {:ok, %{did: did, handle: handle}} <- Latch.callback(@client, params) do
      {:ok, auth(did, handle)}
    end
  end

  def auth(did, handle) do
    %Ueberauth.Auth{
      provider: :atproto,
      uid: did,
      info: %Ueberauth.Auth.Info{nickname: handle, name: nil, email: nil, image: nil}
    }
  end

  def normalize_handle(handle) when is_binary(handle) do
    handle |> String.trim() |> String.trim_leading("@") |> String.trim()
  end

  def normalize_handle(_handle), do: ""
end
