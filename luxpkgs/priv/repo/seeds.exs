# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Luxpkgs.Repo.insert!(%Luxpkgs.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Luxpkgs.RevokedKeys.RevokedKey
alias Luxpkgs.Packages.Release
alias Luxpkgs.Accounts.User
alias Luxpkgs.Repo
alias Luxpkgs.Packages.Package

Repo.delete_all(RevokedKey)
Repo.delete_all(Release)
Repo.delete_all(Package)

# Users are kept so logins survive a reseed.

luxpkgs_rockspec = """
rockspec_format = "3.0"
package = "luxpkgs"
version = "1.0.0-1"
source = {
  url = "git+https://github.com/lumen-oss/luxpkgs",
  tag = "v1.0.0"
}
description = {
  summary = "A package manager for Lua",
  detailed = [[
    Luxpkgs is a modern package manager for Lua, providing a curated
    registry of Lua packages with seamless installation and management.
  ]],
  homepage = "https://github.com/lumen-oss/luxpkgs",
  license = "MIT"
}
dependencies = {
  "lua >= 5.1"
}
build = {
  type = "builtin",
  modules = {
    luxpkgs = "src/luxpkgs/init.lua"
  }
}
"""

File.write!(
  Application.app_dir(:luxpkgs, "priv/static/releases/luxpkgs-1.0.0-1.rockspec"),
  luxpkgs_rockspec
)

luarocks_rockspec = """
rockspec_format = "3.0"
package = "luarocks"
version = "0.2.0-1"
source = {
  url = "git+https://github.com/lumen-oss/luarocks",
  tag = "v0.2.0"
}
description = {
  summary = "A package manager for Lua",
  detailed = [[
    LuaRocks is a package manager for the Lua programming language.
    It allows you to install and manage Lua libraries and C modules.
  ]],
  homepage = "https://github.com/lumen-oss/luarocks",
  license = "MIT"
}
dependencies = {
  "lua >= 5.1"
}
build = {
  type = "builtin",
  modules = {
    luarocks = "src/luarocks/init.lua"
  }
}
"""

File.write!(
  Application.app_dir(:luxpkgs, "priv/static/releases/luarocks-0.2.0-1.rockspec"),
  luarocks_rockspec
)

user =
  Repo.get_by(User, email: "admin@example.com") ||
    Repo.insert!(%User{
      email: "admin@example.com",
      provider: "github",
      username: "admin",
      aka: "admin"
    })

package =
  Repo.insert!(%Package{
    name: "luxpkgs",
    summary:
      "A particularly long summary for the package to test line clamping in the UI. This summary is intentionally made long so that we can observe how the line clamping behaves in the user interface.",
    description: "Full description of the package",
    user_id: user.id
  })

Repo.insert!(%Release{
  version: "1.0.0",
  rockspec_path: "luxpkgs-1.0.0-1.rockspec",
  package_id: package.id
})

Repo.insert!(%Release{
  version: "1.0.1",
  rockspec_path: "luxpkgs-1.0.0-1.rockspec",
  package_id: package.id
})

# ------------------------------------------------

package2 =
  Repo.insert!(%Package{
    name: "luarocks",
    summary: "The other epic Lua site",
    description: "Full description of the package",
    user_id: user.id
  })

Repo.insert!(%Release{
  version: "0.2.0",
  rockspec_path: "luarocks-0.2.0-1.rockspec",
  package_id: package2.id
})

# ------------------------------------------------

package3 =
  Repo.insert!(%Package{
    name: "sweetie.nvim",
    summary: "Neovim colorscheme",
    description: "A clean, delightful and highly customizable Neovim colorscheme written in Lua",
    user_id: user.id
  })

Repo.insert!(%Release{
  version: "3.2.0",
  rockspec: "<content>",
  package_id: package3.id
})

# ------------------------------------------------

# Add a bunch of filler packages

for i <- 1..25 do
  package4 =
    Repo.insert!(%Package{
      name: "busted-#{i}",
      summary: "Elegant Lua unit testing",
      description: "Full description of the package",
      user_id: user.id
    })

  Repo.insert!(%Release{
    version: "2.#{i}.0",
    rockspec: "<content>",
    package_id: package4.id
  })
end

# ------------------------------------------------

# Moderation examples: visible to the owner at /package/<name>, absent everywhere public.
# Set DEMO_OWNER_EMAIL to your own account email to test the owner banner.
demo_owner =
  case System.get_env("DEMO_OWNER_EMAIL") do
    nil -> user
    email -> Repo.get_by!(User, email: email)
  end

hidden_package =
  Repo.insert!(%Package{
    name: "hidden-demo",
    summary: "Hidden package used to try out moderation",
    description: "Only the owner can see this package page.",
    user_id: demo_owner.id,
    status: :hidden,
    moderation_note: "Hidden by a moderator for testing."
  })

Repo.insert!(%Release{
  version: "1.0.0",
  rockspec_path: "luxpkgs-1.0.0-1.rockspec",
  package_id: hidden_package.id
})

yanked_package =
  Repo.insert!(%Package{
    name: "yanked-demo",
    summary: "Package with a yanked release used to try out yanking",
    description: "The 2.0.0 release is yanked, so 1.0.0 stays the latest download.",
    user_id: demo_owner.id
  })

Repo.insert!(%Release{
  version: "1.0.0",
  rockspec_path: "luxpkgs-1.0.0-1.rockspec",
  package_id: yanked_package.id
})

Repo.insert!(%Release{
  version: "2.0.0",
  rockspec_path: "luxpkgs-1.0.0-1.rockspec",
  package_id: yanked_package.id,
  yanked_at: DateTime.utc_now() |> DateTime.truncate(:second)
})
