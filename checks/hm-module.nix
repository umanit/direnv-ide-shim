# What the home-manager module actually produces, rather than merely that it
# evaluates. This is the part most exposed to home-manager API drift: the
# module leans on xdg.desktopEntries and xdg.mimeApps, both of which have
# changed shape before.
{
  lib,
  pkgs,
  runCommand,
  writeShellScriptBin,
  home-manager,
}:

let
  fakePhpstorm = writeShellScriptBin "phpstorm" ''echo "phpstorm $*"'';

  # A scheme list that is not the default, so the test tells a working
  # `schemes` option apart from hardcoded values that happen to match.
  schemes = [
    "phpstorm"
    "custom"
  ];

  hmConfig = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      ../modules/home-manager/phpstorm-url-handler.nix
      {
        home.username = "test";
        home.homeDirectory = "/home/test";
        home.stateVersion = "26.05";

        programs.phpstorm-url-handler = {
          enable = true;
          phpstorm = fakePhpstorm;
          inherit schemes;
        };
      }
    ];
  };

  desktopItem = lib.head (
    lib.filter (p: lib.hasInfix "phpstorm-url-handler.desktop" (p.name or "")) (
      hmConfig.config.home.packages
    )
  );

  mimeapps = hmConfig.config.xdg.configFile."mimeapps.list".source;
in
runCommand "check-hm-module"
  {
    inherit mimeapps;
    desktop = "${desktopItem}/share/applications/phpstorm-url-handler.desktop";
    handler = lib.getExe hmConfig.config.programs.phpstorm-url-handler.package;
  }
  ''
    set -uo pipefail
    # stdenv runs this with errexit on, and these checks run failing commands
    # on purpose to inspect their status, so errexit has to go.
    set +e

    failures=0

    # want <label> <file> <line>
    want() {
      local label="$1" file="$2" line="$3"

      if grep -qxF "$line" "$file"; then
        echo "ok   $label"
        return
      fi

      echo "FAIL $label"
      echo "  expected line: $line"
      echo "  in:"
      sed 's/^/    /' "$file"
      failures=$((failures + 1))
    }

    echo "--- desktop entry"
    want "registers both schemes, in order" "$desktop" \
      "MimeType=x-scheme-handler/phpstorm;x-scheme-handler/custom"
    want "runs the handler binary with the URL" "$desktop" "Exec=$handler %u"
    want "stays out of the app launcher" "$desktop" "NoDisplay=true"
    want "carries the PhpStorm icon" "$desktop" "Icon=phpstorm"

    echo "--- mimeapps.list"
    want "default app for phpstorm://" "$mimeapps" \
      "x-scheme-handler/phpstorm=phpstorm-url-handler.desktop"
    want "default app for custom://" "$mimeapps" \
      "x-scheme-handler/custom=phpstorm-url-handler.desktop"

    # The `phpstorm` option has to reach the built script, otherwise overriding
    # it silently does nothing and the handler drives the wrong IDE.
    echo "--- phpstorm option"
    if grep -qF "${fakePhpstorm}/bin/phpstorm" "$handler"; then
      echo "ok   the phpstorm option reaches the generated script"
    else
      echo "FAIL the phpstorm option does not reach the generated script"
      failures=$((failures + 1))
    fi

    if [ "$failures" -ne 0 ]; then
      echo "$failures check(s) failed" >&2
      exit 1
    fi

    touch $out
  ''
