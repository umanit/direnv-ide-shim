# The shim's two tricky paths: the loop guard that stops it calling itself
# forever outside a direnv project, and the PATH fallback that lets a real
# system binary take over when there is one.
{
  lib,
  runCommand,
  writeShellScriptBin,
  writeTextFile,
  callPackage,
  direnv,
}:

let
  shims = callPackage ../pkgs/direnv-ide-shim.nix { tools = [ "php" ]; };

  # Stands in for a system-wide PHP (apt, Homebrew…) on a non-NixOS machine.
  systemPhp = writeShellScriptBin "php" ''echo "system php: $*"'';

  # Stands in for the PHP a project's devShell puts on PATH.
  devShellPhp = writeShellScriptBin "php" ''echo "devShell php: $*"'';
in
runCommand "check-shim-fallback"
  {
    nativeBuildInputs = [ direnv ];
    inherit shims systemPhp devShellPhp;
  }
  ''
    set -uo pipefail
    # stdenv runs this with errexit on, and these checks run failing commands
    # on purpose to inspect their status, so errexit has to go.
    set +e

    export HOME="$PWD/home"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_CONFIG_HOME="$HOME/.config"
    mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"

    base="$PATH"
    failures=0

    # check <label> <expected status> <expected output> <PATH> [cwd]
    check() {
      local label="$1" want_status="$2" want_out="$3" path="$4" cwd="''${5:-$PWD}"

      local got_out got_status
      got_out="$(cd "$cwd" && PATH="$path" php --version 2>/dev/null)"
      got_status=$?

      if [ "$got_out" = "$want_out" ] && [ "$got_status" = "$want_status" ]; then
        echo "ok   $label"
        return
      fi

      echo "FAIL $label"
      echo "  want (''${want_status}): $want_out"
      echo "   got (''${got_status}): $got_out"
      failures=$((failures + 1))
    }

    # Outside any direnv project, with nothing else named php to fall back to,
    # the guard has to break the loop rather than recurse until the stack dies.
    check "no project, no fallback" 127 "" "$shims/bin:$base"

    # Same, but a real php exists elsewhere on PATH: it wins over giving up.
    check "no project, system php" 0 "system php: --version" \
      "$shims/bin:$systemPhp/bin:$base"

    # The shim must not shadow a system php that comes first on PATH either.
    check "system php first on PATH" 0 "system php: --version" \
      "$systemPhp/bin:$shims/bin:$base"

    # The error message has to name the tool and say where it looked.
    message="$(PATH="$shims/bin:$base" php --version 2>&1 >/dev/null)"
    case "$message" in
      "php: no php available for "*"(no direnv devShell active here, and none elsewhere on PATH)")
        echo "ok   error message names the tool and the two places it looked" ;;
      *)
        echo "FAIL error message"
        echo "   got: $message"
        failures=$((failures + 1)) ;;
    esac

    # Inside a direnv project, the shim must land on the PATH the .envrc sets up,
    # which is what makes one machine-wide binary work for every project.
    project="$PWD/project"
    mkdir -p "$project"
    echo "export PATH=\"$devShellPhp/bin:\$PATH\"" > "$project/.envrc"
    (cd "$project" && direnv allow) 2>/dev/null

    check "direnv project wins" 0 "devShell php: --version" \
      "$shims/bin:$systemPhp/bin:$base" "$project"

    if [ "$failures" -ne 0 ]; then
      echo "$failures check(s) failed" >&2
      exit 1
    fi

    touch $out
  ''
