# Every URL shape the handler claims to accept, checked against the exact
# argument list it hands to PhpStorm. The real PhpStorm is swapped for a stub
# that prints its arguments: the point is what the handler decides, and pulling
# a ~1.5 GB unfree IDE into CI to learn that would be absurd.
{
  lib,
  runCommand,
  writeShellScriptBin,
  callPackage,
}:

let
  fakePhpstorm = writeShellScriptBin "phpstorm" ''
    printf 'phpstorm'
    printf ' [%s]' "$@"
    echo
  '';

  handler = callPackage ../pkgs/phpstorm-url-handler.nix { phpstorm = fakePhpstorm; };
in
runCommand "check-handler-parsing" { nativeBuildInputs = [ handler ]; } ''
  set -uo pipefail
  # stdenv runs this with errexit on, and these checks run failing commands
  # on purpose to inspect their status, so errexit has to go.
  set +e

  project="$PWD/project"
  mkdir -p "$project/.idea" "$project/src"
  : > "$project/src/Foo.php"

  # No .idea above it, so the handler has no project to pass.
  orphan="$PWD/orphan"
  mkdir -p "$orphan"
  : > "$orphan/Bar.php"

  failures=0

  # check <label> <expected status> <expected output> [args...]
  check() {
    local label="$1" want_status="$2" want_out="$3"
    shift 3

    local got_out got_status
    got_out="$(phpstorm-url-handler "$@" 2>&1)"
    got_status=$?

    if [ "$got_out" = "$want_out" ] && [ "$got_status" = "$want_status" ]; then
      echo "ok   $label"
      return
    fi

    echo "FAIL $label"
    echo "       args: $*"
    echo "  want (''${want_status}): $want_out"
    echo "   got (''${got_status}): $got_out"
    failures=$((failures + 1))
  }

  file="$project/src/Foo.php"
  inProject="phpstorm [$project] [--line] [42] [$file]"

  check "file= with line="        0 "$inProject" "phpstorm://open?file=$file&line=42"
  check "url=file:// with line="  0 "$inProject" "phpstorm://open?url=file://$file&line=42"
  check "file= with :line"        0 "$inProject" "phpstorm://open?file=$file:42"
  check "url=file:// with :line"  0 "$inProject" "phpstorm://open?url=file://$file:42"

  # --line is refused unless a project directory comes first, so a file with no
  # .idea above it opens without its line number rather than not at all.
  check "no project, line dropped" 0 "phpstorm [$orphan/Bar.php]" \
    "phpstorm://open?file=$orphan/Bar.php&line=42"

  check "no line at all" 0 "phpstorm [$project] [$file]" "phpstorm://open?file=$file"

  # Percent- and plus-escapes survive the browser and the desktop portal.
  check "percent and plus escapes" 0 "phpstorm [/nonexistent/some file.php]" \
    "phpstorm://open?file=%2Fnonexistent%2Fsome+file.php&line=7"

  # The line number is ours to read even when the query puts it first.
  check "line= before file=" 0 "$inProject" "phpstorm://open?line=42&file=$file"

  check "query without a file" 2 \
    "phpstorm-url-handler: no file found in 'phpstorm://open'" "phpstorm://open"

  check "no argument at all" 2 \
    "phpstorm-url-handler: usage: phpstorm-url-handler <phpstorm://open?file=...&line=...>"

  if [ "$failures" -ne 0 ]; then
    echo "$failures check(s) failed" >&2
    exit 1
  fi

  touch $out
''
