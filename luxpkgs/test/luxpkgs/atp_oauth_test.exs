defmodule Luxpkgs.AtpOauthTest do
  use ExUnit.Case, async: true

  test "the Latch client and its store are supervised" do
    assert Process.whereis(Luxpkgs.AtpOauth.Client)
    assert Process.whereis(Luxpkgs.AtpOauthStore)
    assert :ets.whereis(Luxpkgs.AtpOauthStore_requests) != :undefined
  end
end
