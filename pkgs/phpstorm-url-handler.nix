{
  lib,
  writeShellApplication,
  jetbrains,
  wmctrl,
  phpstorm ? jetbrains.phpstorm,
}:

writeShellApplication {
  name = "phpstorm-url-handler";

  runtimeInputs = [ wmctrl ];

  text = ''
    # Opens the file a phpstorm:// link points at, at the right line, in a
    # running PhpStorm. Such links come from Symfony's profiler and error
    # pages, Whoops, Xdebug and friends. Accepted shapes:
    #
    #   phpstorm://open?file=<path>&line=<n>
    #   phpstorm://open?url=file://<path>&line=<n>
    #   phpstorm://open?file=<path>:<n>
    #   phpstorm://open?url=file://<path>:<n>
    #
    # Derived from https://github.com/sanduhrs/phpstorm-url-handler (GPL),
    # by Stefan Auditor <stefan@auditor.email>.

    url="''${1:-}"
    if [ -z "$url" ]; then
      echo "phpstorm-url-handler: usage: phpstorm-url-handler <phpstorm://open?file=...&line=...>" >&2
      exit 2
    fi

    # Percent- and plus-escapes survive the trip through the browser and the
    # desktop portal, so decode before touching the path.
    urldecode() {
      local value="''${1//+/ }"
      printf '%b' "''${value//%/\\x}"
    }

    # Everything after the first '?' is the query string; a URL without one
    # leaves no parameter to match below, and fails on the empty file check.
    query="''${url#*\?}"

    file=""
    line=""
    IFS='&' read -ra params <<< "$query"
    for param in "''${params[@]}"; do
      case "$param" in
        file=*) file="$(urldecode "''${param#file=}")" ;;
        url=*) file="$(urldecode "''${param#url=}")" ;;
        line=*) line="''${param#line=}" ;;
      esac
    done

    file="''${file#file://}"

    # The `?file=<path>:<n>` shape glues the line number onto the path instead
    # of passing it as its own parameter.
    if [ -z "$line" ] && [[ "$file" =~ ^(.*):([0-9]+)$ ]]; then
      file="''${BASH_REMATCH[1]}"
      line="''${BASH_REMATCH[2]}"
    fi

    if [ -z "$file" ]; then
      echo "phpstorm-url-handler: no file found in '$url'" >&2
      exit 2
    fi

    # PhpStorm's CLI only accepts --line when the first argument is a project
    # directory: since 2026.2 the launcher rejects `phpstorm --line <n> <file>`
    # outright with "unrecognized option: --line". Walk up from the file to the
    # nearest .idea/ to recover the project it belongs to.
    project=""
    dir="$(dirname "$file")"
    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
      if [ -d "$dir/.idea" ]; then
        project="$dir"
        break
      fi
      dir="$(dirname "$dir")"
    done

    if [ -n "$project" ] && [ -n "$line" ]; then
      ${lib.getExe phpstorm} "$project" --line "$line" "$file"
    elif [ -n "$project" ]; then
      ${lib.getExe phpstorm} "$project" "$file"
    else
      # Without a project directory --line is refused, so the line number has
      # to be dropped; opening the file alone still beats opening nothing.
      ${lib.getExe phpstorm} "$file"
    fi

    # Raising the window is best-effort: it only works on X11, PhpStorm may not
    # have created the window yet, and an empty match would make `wmctrl -i -a`
    # swallow the next argument instead of failing.
    window="$(wmctrl -l 2>/dev/null | grep -F "$(basename "$file")" | tail -n 1 | cut -d ' ' -f1 || true)"
    if [ -n "$window" ]; then
      wmctrl -i -a "$window" || true
    fi
  '';

  meta = {
    description = "Handler for phpstorm:// links, opening the target file at the right line in PhpStorm";
    homepage = "https://github.com/umanit/direnv-ide-shim";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
    mainProgram = "phpstorm-url-handler";
  };
}
