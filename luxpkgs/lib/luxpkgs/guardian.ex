defmodule Luxpkgs.Guardian do
  alias Luxpkgs.Accounts.Scope
  alias Luxpkgs.Accounts.User
  use Guardian, otp_app: :luxpkgs

  def subject_for_token(%User{id: id}, %{
        "allowed_packages" => _,
        "write_restriction" => _,
        "require_tfa" => _
      }) do
    {:ok, to_string(id)}
  end

  def subject_for_token(%User{id: id}, %{
        "allowed_packages" => _,
        "write_restriction" => _
      }) do
    {:ok, to_string(id)}
  end

  def subject_for_token(%User{}, _claims) do
    {:error, :invalid_claims}
  end

  def subject_for_token(_, _) do
    {:error, :expected_user_struct}
  end

  def resource_from_claims(
        %{
          "sub" => id,
          "allowed_packages" => allowed_packages,
          "write_restriction" => write_restriction
        } = claims
      ) do
    case Luxpkgs.Accounts.get_user(id) do
      %User{} = user ->
        if User.suspended?(user) do
          {:error, :user_suspended}
        else
          {:ok,
           Scope.for_jwt(%{
             user: user,
             package_whitelist: allowed_packages,
             write_restricted: write_restriction,
             require_tfa: Map.get(claims, "require_tfa", true)
           })}
        end

      nil ->
        {:error, :user_not_found}
    end
  end

  def resource_from_claims(_claims) do
    {:error, :invalid_token_not_enough_claims}
  end
end
