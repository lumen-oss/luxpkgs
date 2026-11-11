defmodule LuxpkgsRockspecVerifier.RockspecTest do
  use ExUnit.Case, async: true

  alias LuxpkgsRockspecVerifier.Rockspec

  @valid_rockspec """
  rockspec_format = "3.0"
  package = "my-package"
  version = "1.0.0"
  source = { url = "https://github.com/user/repo/archive/v1.0.0.tar.gz" }
  build = { type = "builtin" }
  """

  describe "valid rockspecs" do
    test "passes with all valid fields and https URL" do
      assert Rockspec.verify(@valid_rockspec, %{
               expected_name: "my-package",
               expected_version: "1.0.0"
             })
    end

    test "passes with git+https URL and tag" do
      rockspec = """
      rockspec_format = "3.0"
      package = "my-package"
      version = "2.0.0"
      source = { url = "git+https://github.com/user/repo.git", tag = "v2.0.0" }
      build = { type = "builtin" }
      """

      assert Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "2.0.0"})
    end

    test "passes with git:// URL and tag" do
      rockspec = """
      rockspec_format = "3.0"
      package = "my-package"
      version = "2.0.0"
      source = { url = "git://github.com/user/repo.git", tag = "v2.0.0" }
      build = { type = "builtin" }
      """

      assert Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "2.0.0"})
    end

    test "passes with git+https URL and hash" do
      rockspec = """
      rockspec_format = "3.0"
      package = "my-package"
      version = "2.0.0"
      source = { url = "git+https://github.com/user/repo.git", hash = "abc123def456" }
      build = { type = "builtin" }
      """

      assert Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "2.0.0"})
    end

    test "passes with package name containing hyphens" do
      rockspec = """
      rockspec_format = "3.0"
      package = "my-cool-package"
      version = "0.1.0"
      source = { url = "https://example.com/pkg-0.1.0.tar.gz" }
      build = { type = "builtin" }
      """

      assert Rockspec.verify(rockspec, %{
               expected_name: "my-cool-package",
               expected_version: "0.1.0"
             })
    end

    test "passes with package name containing underscores" do
      rockspec = """
      rockspec_format = "3.0"
      package = "my_cool_package"
      version = "3.2.1"
      source = { url = "https://example.com/pkg.tar.gz" }
      build = { type = "builtin" }
      """

      assert Rockspec.verify(rockspec, %{
               expected_name: "my_cool_package",
               expected_version: "3.2.1"
             })
    end

    test "passes with complex semver version" do
      rockspec = """
      rockspec_format = "3.0"
      package = "pkg"
      version = "10.200.3000"
      source = { url = "https://example.com/pkg.tar.gz" }
      build = { type = "builtin" }
      """

      assert Rockspec.verify(rockspec, %{expected_name: "pkg", expected_version: "10.200.3000"})
    end
  end

  describe "expected_name validation - denied" do
    test "rejects expected_name with spaces" do
      refute Rockspec.verify(@valid_rockspec, %{
               expected_name: "my package",
               expected_version: "1.0.0"
             })
    end

    test "rejects expected_name with special characters" do
      refute Rockspec.verify(@valid_rockspec, %{expected_name: "@foo", expected_version: "1.0.0"})
    end

    test "rejects expected_name with dots" do
      refute Rockspec.verify(@valid_rockspec, %{
               expected_name: "my.package",
               expected_version: "1.0.0"
             })
    end

    test "rejects expected_name with forward slash" do
      refute Rockspec.verify(@valid_rockspec, %{
               expected_name: "my/package",
               expected_version: "1.0.0"
             })
    end

    test "rejects expected_name with backslash" do
      refute Rockspec.verify(@valid_rockspec, %{
               expected_name: "my\\package",
               expected_version: "1.0.0"
             })
    end

    test "rejects empty expected_name" do
      refute Rockspec.verify(@valid_rockspec, %{expected_name: "", expected_version: "1.0.0"})
    end

    test "rejects expected_name with spaces and special chars" do
      refute Rockspec.verify(@valid_rockspec, %{
               expected_name: "my package!@#",
               expected_version: "1.0.0"
             })
    end
  end

  describe "expected_version validation - denied" do
    test "rejects non-semver expected_version" do
      refute Rockspec.verify(@valid_rockspec, %{
               expected_name: "my-package",
               expected_version: "abc"
             })
    end

    test "rejects expected_version with only major.minor" do
      refute Rockspec.verify(@valid_rockspec, %{
               expected_name: "my-package",
               expected_version: "1.0"
             })
    end

    test "rejects empty expected_version" do
      refute Rockspec.verify(@valid_rockspec, %{expected_name: "my-package", expected_version: ""})
    end

    test "rejects expected_version with letters" do
      refute Rockspec.verify(@valid_rockspec, %{
               expected_name: "my-package",
               expected_version: "1.0.0a"
             })
    end

    test "rejects expected_version with v prefix" do
      refute Rockspec.verify(@valid_rockspec, %{
               expected_name: "my-package",
               expected_version: "v1.0.0"
             })
    end

    test "rejects expected_version with spaces" do
      refute Rockspec.verify(@valid_rockspec, %{
               expected_name: "my-package",
               expected_version: "1 .0.0"
             })
    end
  end

  describe "Lua execution failures - denied" do
    test "rejects Lua syntax error" do
      rockspec = "this is not valid lua {{{{"
      refute Rockspec.verify(rockspec, %{expected_name: "pkg", expected_version: "1.0.0"})
    end

    test "rejects empty Lua input" do
      refute Rockspec.verify("", %{expected_name: "pkg", expected_version: "1.0.0"})
    end

    test "rejects Lua returning a string instead of table" do
      rockspec = """
      rockspec_format = "3.0"
      package = "pkg"
      return "not a table"
      """

      refute Rockspec.verify(rockspec, %{expected_name: "pkg", expected_version: "1.0.0"})
    end

    test "rejects Lua returning a number instead of table" do
      rockspec = """
      rockspec_format = "3.0"
      package = "pkg"
      return 42
      """

      refute Rockspec.verify(rockspec, %{expected_name: "pkg", expected_version: "1.0.0"})
    end

    test "rejects Lua returning nil" do
      rockspec = """
      rockspec_format = "3.0"
      package = "pkg"
      return nil
      """

      refute Rockspec.verify(rockspec, %{expected_name: "pkg", expected_version: "1.0.0"})
    end

    test "rejects Lua with infinite loop (exceeds reduction limit)" do
      rockspec = """
      while true do end
      """

      refute Rockspec.verify(rockspec, %{expected_name: "pkg", expected_version: "1.0.0"})
    end

    test "rejects Lua trying to require modules" do
      rockspec = """
      require("string")
      rockspec_format = "3.0"
      """

      refute Rockspec.verify(rockspec, %{expected_name: "pkg", expected_version: "1.0.0"})
    end

    test "rejects Lua trying to access io library" do
      rockspec = """
      local f = io and io.open or nil
      rockspec_format = "3.0"
      """

      refute Rockspec.verify(rockspec, %{expected_name: "pkg", expected_version: "1.0.0"})
    end

    test "rejects Lua trying to access os library" do
      rockspec = """
      local f = os and os.time or nil
      rockspec_format = "3.0"
      """

      refute Rockspec.verify(rockspec, %{expected_name: "pkg", expected_version: "1.0.0"})
    end
  end

  describe "rockspec_format validation - denied" do
    test "rejects missing rockspec_format" do
      rockspec = """
      package = "my-package"
      version = "1.0.0"
      source = { url = "https://example.com/pkg.tar.gz" }
      build = { type = "builtin" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects rockspec_format '2.0'" do
      rockspec = """
      rockspec_format = "2.0"
      package = "my-package"
      version = "1.0.0"
      source = { url = "https://example.com/pkg.tar.gz" }
      build = { type = "builtin" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects rockspec_format as number instead of string" do
      rockspec = """
      rockspec_format = 3.0
      package = "my-package"
      version = "1.0.0"
      source = { url = "https://example.com/pkg.tar.gz" }
      build = { type = "builtin" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects rockspec_format '4.0'" do
      rockspec = """
      rockspec_format = "4.0"
      package = "my-package"
      version = "1.0.0"
      source = { url = "https://example.com/pkg.tar.gz" }
      build = { type = "builtin" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects rockspec_format as empty string" do
      rockspec = """
      rockspec_format = ""
      package = "my-package"
      version = "1.0.0"
      source = { url = "https://example.com/pkg.tar.gz" }
      build = { type = "builtin" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end
  end

  describe "package name mismatch - denied" do
    test "rejects when rockspec package differs from expected_name" do
      rockspec = """
      rockspec_format = "3.0"
      package = "other-package"
      version = "1.0.0"
      source = { url = "https://example.com/pkg.tar.gz" }
      build = { type = "builtin" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects when rockspec package is empty but expected_name is not" do
      rockspec = """
      rockspec_format = "3.0"
      package = ""
      version = "1.0.0"
      source = { url = "https://example.com/pkg.tar.gz" }
      build = { type = "builtin" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects case-sensitive package name mismatch" do
      rockspec = """
      rockspec_format = "3.0"
      package = "My-Package"
      version = "1.0.0"
      source = { url = "https://example.com/pkg.tar.gz" }
      build = { type = "builtin" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end
  end

  describe "version mismatch - denied" do
    test "rejects when rockspec version differs from expected_version" do
      rockspec = """
      rockspec_format = "3.0"
      package = "my-package"
      version = "2.0.0"
      source = { url = "https://example.com/pkg.tar.gz" }
      build = { type = "builtin" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects when rockspec version is empty but expected_version is not" do
      rockspec = """
      rockspec_format = "3.0"
      package = "my-package"
      version = ""
      source = { url = "https://example.com/pkg.tar.gz" }
      build = { type = "builtin" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end
  end

  describe "source validation - denied" do
    test "rejects missing source entirely" do
      rockspec = """
      rockspec_format = "3.0"
      package = "my-package"
      version = "1.0.0"
      build = { type = "builtin" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects source with no url key" do
      rockspec = """
      rockspec_format = "3.0"
      package = "my-package"
      version = "1.0.0"
      source = { tag = "v1.0.0" }
      build = { type = "builtin" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects source with only file path (no url key)" do
      rockspec = """
      rockspec_format = "3.0"
      package = "my-package"
      version = "1.0.0"
      source = { dir = "/some/path" }
      build = { type = "builtin" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end
  end

  describe "build validation - denied" do
    test "rejects missing build entirely" do
      rockspec = """
      rockspec_format = "3.0"
      package = "my-package"
      version = "1.0.0"
      source = { url = "https://example.com/pkg.tar.gz" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects build with no type key" do
      rockspec = """
      rockspec_format = "3.0"
      package = "my-package"
      version = "1.0.0"
      source = { url = "https://example.com/pkg.tar.gz" }
      build = { modules = "src" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects build as empty table" do
      rockspec = """
      rockspec_format = "3.0"
      package = "my-package"
      version = "1.0.0"
      source = { url = "https://example.com/pkg.tar.gz" }
      build = {}
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end
  end

  describe "multiple validation failures - denied" do
    test "rejects when both package and version mismatch" do
      rockspec = """
      rockspec_format = "3.0"
      package = "wrong-package"
      version = "9.9.9"
      source = { url = "https://example.com/pkg.tar.gz" }
      build = { type = "builtin" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects when format is wrong and source is missing" do
      rockspec = """
      rockspec_format = "2.0"
      package = "my-package"
      version = "1.0.0"
      build = { type = "builtin" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects when format, source, and build are all missing" do
      rockspec = """
      package = "my-package"
      version = "1.0.0"
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end
  end

  describe "tricky Lua patterns - denied" do
    test "rejects Lua that sets globals after returning" do
      rockspec = """
      local result = {
        rockspec_format = "3.0",
        package = "my-package",
        version = "1.0.0",
        source = { url = "https://example.com/pkg.tar.gz" },
        build = { type = "builtin" }
      }
      return result
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects Lua with extremely long string (potential memory exhaustion)" do
      long_string = String.duplicate("a", 10_000)

      rockspec = """
      rockspec_format = "#{long_string}"
      package = "my-package"
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects Lua that defines fields as strings instead of tables" do
      rockspec = """
      rockspec_format = "3.0"
      package = "my-package"
      version = "1.0.0"
      source = "https://example.com/pkg.tar.gz"
      build = "builtin"
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end

    test "rejects Lua with nested tables but no required fields" do
      rockspec = """
      rockspec_format = "3.0"
      package = "my-package"
      version = "1.0.0"
      source = { location = "https://example.com/pkg.tar.gz" }
      build = { backend = "cmake" }
      """

      refute Rockspec.verify(rockspec, %{expected_name: "my-package", expected_version: "1.0.0"})
    end
  end

  describe "metadata extraction" do
    @metadata_rockspec """
    rockspec_format = "3.0"
    package = "meta"
    version = "1.0.0"
    source = { url = "git+https://example.com/meta.git", tag = "1.0.0" }
    build = { type = "cmake" }
    description = {
      summary = "A package",
      detailed = "# Meta\\n\\nLong description.",
      license = "MIT",
      homepage = "https://example.com",
      issues_url = "https://example.com/issues",
      labels = { "testing", "lua" }
    }
    lua = ">= 5.1"
    supported_platforms = { "unix", "!windows" }
    dependencies = { "lua >= 5.1", "foo >= 1.0" }
    external_dependencies = {
      OPENSSL = { header = "openssl/ssl.h", library = "ssl" },
      ZLIB = "z"
    }
    """

    test "verify_with_metadata returns nested rockspec fields" do
      assert {:ok, metadata} =
               Rockspec.verify_with_metadata(@metadata_rockspec, %{
                 expected_name: "meta",
                 expected_version: "1.0.0"
               })

      assert metadata["summary"] == "A package"
      assert metadata["detailed"] == "# Meta\n\nLong description."
      assert metadata["license"] == "MIT"
      assert metadata["homepage"] == "https://example.com"
      assert metadata["issues_url"] == "https://example.com/issues"
      assert metadata["labels"] == ["testing", "lua"]
      assert metadata["lua"] == ">= 5.1"
      assert metadata["platforms"] == ["unix", "!windows"]
      assert metadata["dependencies"] == ["lua >= 5.1", "foo >= 1.0"]

      assert metadata["external_dependencies"] == [
               %{"name" => "OPENSSL", "header" => "openssl/ssl.h", "library" => "ssl"},
               %{"name" => "ZLIB", "library" => "z"}
             ]

      assert metadata["build_type"] == "cmake"
    end

    test "parse returns nested summary and description plus metadata" do
      assert {:ok, parsed} = Rockspec.parse(@metadata_rockspec)

      assert parsed.package == "meta"
      assert parsed.version == "1.0.0"
      assert parsed.summary == "A package"
      assert parsed.description == "# Meta\n\nLong description."
      assert parsed.metadata["license"] == "MIT"
    end

    test "parse falls back to top-level summary and description strings" do
      rockspec = """
      package = "legacy"
      version = "1.0.0"
      summary = "Legacy summary"
      description = "Legacy description"
      """

      assert {:ok, parsed} = Rockspec.parse(rockspec)
      assert parsed.summary == "Legacy summary"
      assert parsed.description == "Legacy description"
    end

    test "metadata ignores fields with unexpected shapes" do
      rockspec = """
      rockspec_format = "3.0"
      package = "meta"
      version = "1.0.0"
      source = { url = "https://example.com/meta.tar.gz" }
      build = { type = "builtin" }
      description = {
        summary = "A package",
        homepage = 123,
        labels = "solo"
      }
      dependencies = { 1, "ok" }
      supported_platforms = { true }
      external_dependencies = { BROKEN = 1 }
      """

      assert {:ok, metadata} =
               Rockspec.verify_with_metadata(rockspec, %{
                 expected_name: "meta",
                 expected_version: "1.0.0"
               })

      assert metadata["summary"] == "A package"
      assert metadata["labels"] == ["solo"]
      assert metadata["dependencies"] == ["ok"]
      refute Map.has_key?(metadata, "homepage")
      refute Map.has_key?(metadata, "platforms")
      refute Map.has_key?(metadata, "external_dependencies")
    end
  end
end
