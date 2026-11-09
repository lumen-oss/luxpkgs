defmodule Luxpkgs.AdminFixtures do
  alias Luxpkgs.Admin.Admin
  alias Luxpkgs.Repo

  def admin_fixture(attrs \\ %{}) do
    user = Map.get(attrs, :user) || Luxpkgs.AccountsFixtures.user_fixture()
    role = Map.get(attrs, :role, :moderator)
    active = Map.get(attrs, :active, true)

    %Admin{}
    |> Admin.changeset(%{user_id: user.id, role: role, active: active})
    |> Repo.insert!()
  end
end
