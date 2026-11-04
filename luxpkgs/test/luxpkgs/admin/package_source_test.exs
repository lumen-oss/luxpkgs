defmodule Luxpkgs.Admin.PackageSourceTest do
  use ExUnit.Case, async: false

  alias Luxpkgs.Admin.PackageSource
  alias Luxpkgs.Packages.Release

  setup do
    root = Application.get_env(:luxpkgs, :rockspec_storage)
    File.rm_rf!(root)
    File.mkdir_p!(root)

    on_exit(fn ->
      File.rm_rf!(root)
      File.mkdir_p!(root)
    end)

    %{root: root}
  end

  test "reads a rockspec inside the storage directory", %{root: root} do
    File.write!(Path.join(root, "demo-1.0.0.rockspec"), "return { name = 'demo' }")

    assert {:ok, source} =
             PackageSource.read(%Release{rockspec_path: "demo-1.0.0.rockspec"})

    assert source.filename == "demo-1.0.0.rockspec"
    assert source.kind == :rockspec
    assert source.content == "return { name = 'demo' }"
  end

  test "detects lux.toml sources", %{root: root} do
    File.write!(Path.join(root, "demo-1.0.0.toml"), "name = \"demo\"")

    assert {:ok, %{kind: :lux_toml}} =
             PackageSource.read(%Release{rockspec_path: "demo-1.0.0.toml"})
  end

  test "does not read files outside the storage directory", %{root: _root} do
    outside = Path.join(System.tmp_dir!(), "outside-source.rockspec")
    File.write!(outside, "secret")
    on_exit(fn -> File.rm(outside) end)

    assert {:error, :missing_file} =
             PackageSource.read(%Release{rockspec_path: "../outside-source.rockspec"})
  end

  test "rejects files larger than 2 MB", %{root: root} do
    File.write!(Path.join(root, "large-1.0.0.rockspec"), String.duplicate("a", 2_097_153))

    assert {:error, :too_large} =
             PackageSource.read(%Release{rockspec_path: "large-1.0.0.rockspec"})
  end

  test "returns an error when the file is missing" do
    assert {:error, :missing_file} =
             PackageSource.read(%Release{rockspec_path: "missing-1.0.0.rockspec"})
  end
end
