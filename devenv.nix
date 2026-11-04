{ pkgs, config, lib, ... }:

let
  user = config.env.DATABASE_USER;
  pass = config.env.DATABASE_PASS;
in
{
    env.DATABASE_URL="postgres://${user}:${pass}@127.0.0.1/luxpkgs";
    env.MIX_TAILWIND_PATH = "${pkgs.tailwindcss_4}/bin/tailwindcss";
    env.PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    env.PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";

    dotenv = {
        enable = true;
        filename = [ ".env.dev" ".env.prod" ];
    };

    languages.elixir = {
        enable = true;
        lsp.package = pkgs.beamPackages.expert;
    };

    languages.nix.enable = true;

    packages = [
      pkgs.pnpm           # Bundled JS dependencies
      pkgs.alejandra      # Nix formatter
      pkgs.tailwindcss_4  # We cannot use the bundled TailwindCSS CLI from Phoenix on NixOS
      pkgs.inotify-tools  # Required for file watching on Phoenix
      pkgs.watchman       # Required for file watching on TailwindCSS CLI
      pkgs.playwright-mcp # Playwright MCP server using the Nix-managed browsers
    ];

    # https://devenv.sh/services/
    services.postgres = {
        enable = true;
        package = pkgs.postgresql_17;
        initialDatabases = [
          {
            name = "luxpkgs";
            inherit user pass;
          }
          {
            name = "luxpkgs_test";
            inherit user pass;
          }
        ];
        listen_addresses = "127.0.0.1,localhost";
        port = lib.toIntBase10 config.env.DATABASE_PORT;
    };

    tasks = {
      "luxpkgs:setupHex" = {
          exec = "mix local.hex --force --if-missing";
          before = [ "devenv:enterShell" "devenv:enterTest" ];
      };
      "luxpkgs:getDependencies" = {
          exec = "cd ${config.env.DEVENV_ROOT}/luxpkgs; mix deps.get";
          status = "test -d ${config.env.DEVENV_ROOT}/luxpkgs/deps";
          before = [ "devenv:enterShell" "devenv:enterTest" ];
          after = [ "luxpkgs:setupHex" ];
      };
      "luxpkgs:getJSDependencies" = {
          exec = "pnpm --dir ${config.env.DEVENV_ROOT}/luxpkgs/assets/ install";
          status = "test -d ${config.env.DEVENV_ROOT}/luxpkgs/assets/node_modules";
          before = [ "devenv:enterShell" "devenv:enterTest" ];
      };
      "luxpkgs-verifier:getDependencies" = {
          exec = "cd ${config.env.DEVENV_ROOT}/luxpkgs-rockspec-verifier; mix deps.get";
          status = "test -d ${config.env.DEVENV_ROOT}/luxpkgs-rockspec-verifier/deps";
          before = [ "devenv:enterShell" "devenv:enterTest" ];
          after = [ "luxpkgs:setupHex" ];
      };
    };

    processes.luxpkgs.exec = ''
      cd ${config.env.DEVENV_ROOT}/luxpkgs
      # For some reason if there is an empty SSLKEYLOGFILE variable in the environment, Elixir's SSL breaks.
      # Unsetting it if it's empty seems to fix the issue.
      #
      # See: https://github.com/sneako/finch/issues/376
      if [ -n "''${SSLKEYLOGFILE+x}" ] && [ -z "$SSLKEYLOGFILE" ]; then
        unset SSLKEYLOGFILE
      fi
      mix phx.server
    '';

    processes.luxpkgs-rockspec-verifier.exec = ''
      cd ${config.env.DEVENV_ROOT}/luxpkgs-rockspec-verifier
      mix phx.server
    '';

    enterTest = ''
      cd ${config.env.DEVENV_ROOT}/luxpkgs
      mix test
      #cd ${config.env.DEVENV_ROOT}/luxpkgs-rockspec-verifier
      #mix test
    '';
}
