defmodule Luxpkgs.Packages.Release do
  use Ecto.Schema
  import Ecto.Changeset
  import Logger, only: :macros

  schema "releases" do
    field :version, Luxpkgs.Types.Version
    field :rockspec_path, :string
    field :rockspec, :any, virtual: true
    field :download_count, :integer, default: 0
    field :yanked_at, :utc_datetime
    belongs_to :package, Luxpkgs.Packages.Package

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(release, attrs) do
    release
    |> cast(attrs, [:version, :rockspec])
    |> validate_required([:version, :rockspec])
    |> unique_constraint([:version, :package_id], name: :unique_package_version)
    |> validate_version_format()
    |> validate_rockspec(attrs["package"])
  end

  defp validate_version_format(changeset) do
    validate_change(changeset, :version, fn :version, version ->
      if valid_format?(version) do
        []
      else
        [version: "must be a valid semver version string"]
      end
    end)
  end

  defp valid_format?(%Version{pre: [pre]}) when is_integer(pre), do: true
  # sometimes the prerelease can have custom string values
  # TODO(vhyrro): ensure this does not break any ordering logic
  defp valid_format?(%Version{pre: [pre]}) when is_binary(pre), do: true
  defp valid_format?(_), do: false

  defp validate_rockspec(changeset, package) do
    rockspec = get_field(changeset, :rockspec)
    version = get_field(changeset, :version)

    case Application.get_env(:luxpkgs, :rockspec_verification_endpoint)
         |> Req.post(json: %{rockspec: rockspec, package: package, version: to_string(version)}) do
      {:ok, %Req.Response{status: 200}} ->
        changeset
        |> put_change(:rockspec_path, "#{package}-#{version}.rockspec")

      {:ok, %Req.Response{status: 400, body: %{"error" => "Invalid parameters"}}} ->
        Logger.error("Invalid parameters provided to rockspec verification endpoint",
          rockspec: rockspec
        )

        add_error(changeset, :rockspec, "Invalid rockspec")

      {:ok, %Req.Response{status: 422}} ->
        add_error(changeset, :rockspec, "Invalid rockspec")
    end
  end
end
