defmodule LuxpkgsRockspecVerifierWeb.VerifyController do
  use LuxpkgsRockspecVerifierWeb, :controller

  alias LuxpkgsRockspecVerifier.Rockspec

  # Real rockspecs can reach ~40 KB (Kong); 48 KB leaves headroom.
  @max_rockspec_bytes 48 * 1024

  def verify(conn, %{
        "rockspec" => rockspec,
        "package" => expected_name,
        "version" => expected_version
      })
      when is_binary(rockspec) and
             is_binary(expected_name) and
             is_binary(expected_version) and
             byte_size(rockspec) <= @max_rockspec_bytes do
    case Rockspec.verify_with_metadata(rockspec, %{
           expected_name: expected_name,
           expected_version: expected_version
         }) do
      {:ok, metadata} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Rockspec is valid",
          metadata: metadata
        })

      :error ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Rockspec is invalid"
        })
    end
  end

  def verify(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "Invalid parameters"
    })
  end

  def parse(conn, %{"rockspec" => rockspec})
      when is_binary(rockspec) and byte_size(rockspec) <= @max_rockspec_bytes do
    case Rockspec.parse(rockspec) do
      {:ok, parsed} ->
        json(conn, parsed)

      {:error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid rockspec"})
    end
  end

  def parse(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid parameters"})
  end
end
