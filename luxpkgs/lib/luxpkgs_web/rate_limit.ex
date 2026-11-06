defmodule LuxpkgsWeb.RateLimit do
  use Hammer, backend: :ets

  def tier_limits,
    do: %{
      general: {120, 60_000},
      search: {100, 3_600_000},
      write: {10, 3_600_000},
      totp: {5, 300_000},
      report: {5, 86_400_000}
    }

  def hit(tier, key) do
    {limit, period} = Map.fetch!(__MODULE__.tier_limits(), tier)
    __MODULE__.hit(key, period, limit)
  end

  def totp_exceeded?(user_id) do
    match?({:deny, _}, hit(:totp, "user:totp:#{user_id}"))
  end
end
