# direnv-ide-shim

Glue between PhpStorm and PHP projects powered by Nix/direnv. Two independent tools:

- **the shims** (`php`, `composer`, …): fixed-path binaries that resolve, on every call, the `direnv`/Nix environment of the project they are run in, then delegate to the matching real binary;
- **`phpstorm-url-handler`**: the handler for `phpstorm://` links, so that the "open in editor" links of the Symfony profiler, Whoops or Xdebug open the file at the right line.

| | Package | home-manager module |
|---|---|---|
| Shims | `packages.<system>.default` (alias: `.direnv-ide-shim`) | — (a binary on `PATH`, nothing to configure) |
| URL handler | `packages.<system>.phpstorm-url-handler` | `homeModules.phpstorm-url-handler` |

---

# `php` / `composer` shims

## Why

Projects that provide PHP through a Nix `devShell` (e.g. `use flake` in an `.envrc`) expose binaries whose `/nix/store` path changes on every rebuild (`flake.lock` update, garbage collection…). IDEs like PhpStorm require a frozen interpreter path and never re-read it dynamically: after each rebuild the configured interpreter breaks and has to be pointed at the new path by hand.

More subtle: PhpStorm's "Quality Tools" integrations (PHPStan, PHP_CodeSniffer…) don't even invoke the CLI interpreter configured in the settings — they run the `vendor/bin/phpstan`/`vendor/bin/phpcs` script directly, relying on its `#!/usr/bin/env php` shebang. That requires a `php` *literally present on `PATH`*, regardless of any interpreter configured elsewhere in the IDE.

This flake provides a stable indirection point: binaries named exactly like the real tool (`php`, `composer`), installed once machine-wide, valid for **every** Nix/direnv project on the machine — satisfying both shebang `env php` resolution and the explicit interpreter configuration of an IDE.

## How it works

Each shim runs `direnv exec "$PWD" <tool> "$@"`. `direnv` walks up the directory tree itself to find the current project's `.envrc`, so the shim needs to know nothing about the project it is called in. The project's `devShell` puts its own `bin/` entry at the front of PATH, so resolution lands on the project's real binary, not on the shim itself.

**Loop guard + fallback to a system binary**: outside any direnv project (no `.envrc` found), `direnv exec` merely runs the command with the current environment untouched — so a second resolution of the same tool name would land on this very shim again, forever. Each shim therefore sets an environment variable on the first pass; on the second pass (variable already present), instead of giving up right away, it looks for *another* executable of the same name on `PATH` (explicitly excluding itself) and runs it if it finds one — for instance a real system PHP installed through `apt` on a non-NixOS machine. If it finds none (the typical case of a NixOS machine with no global PHP), it fails cleanly with a clear message. The same binary therefore behaves correctly on every machine, with no need to tell NixOS apart from anything else: only what actually exists on the machine's `PATH` changes the outcome.

Prerequisite, per target project: `direnv allow` must have been run at least once (standard `direnv` behaviour, unrelated to this shim).

## Installation

### NixOS / home-manager machine

```nix
inputs.direnv-ide-shim.url = "github:umanit/direnv-ide-shim";
# ...
home.packages = [ inputs.direnv-ide-shim.packages.${pkgs.system}.default ];
```

### Machine with Nix alone (no NixOS), e.g. Ubuntu

```bash
nix profile install "github:umanit/direnv-ide-shim"
```

Either way, `php` / `composer` end up in the user profile — but the exact path depends on how home-manager is wired:

- **standalone home-manager** (`home-manager switch`): `~/.nix-profile/bin/php`.
- **home-manager as a NixOS module** (`useGlobalPkgs = true` / `useUserPackages = true`, e.g. through `nh os switch`): `/etc/profiles/per-user/<user>/bin/php` — this is the case that applies when `~/.nix-profile/` does not exist.
- `nix profile install` (Nix alone, no NixOS/home-manager): `~/.nix-profile/bin/php`.

When in doubt, `command -v php` (once the binary is on the shell's `PATH`) gives the exact path to paste into PhpStorm.

## PhpStorm configuration (per project, once)

- `Settings › PHP › CLI Interpreters` → path to `php` (see above to locate it).
- `Settings › PHP › Composer › Executable` → `composer`.
- Nothing to do for PHPStan/PHP_CodeSniffer: once `php` is on the global `PATH`, their `#!/usr/bin/env php` resolution works on its own.

## Adding a tool

Add its name to the `tools` list in `pkgs/direnv-ide-shim.nix` (e.g. `"symfony"`), rebuild — `symfony` shows up automatically. Without touching the repo, `callPackage ./pkgs/direnv-ide-shim.nix { tools = [ "php" "composer" "symfony" ]; }` does the same.

---

# Development

```bash
nix flake check -L   # evaluates every output, then builds and runs the checks
nix fmt              # nixfmt through treefmt
```

The checks live in `checks/`: URL parsing for the handler, the loop guard and
PATH fallback for the shims, and what the home-manager module actually
produces. They swap PhpStorm for a stub that prints its arguments, so running
them never pulls the real (unfree, ~1.5 GB) IDE. CI runs the same two commands
on every push and pull request.

---

# `phpstorm-url-handler`

## Why

The Symfony profiler, Symfony's error pages, Whoops and Xdebug render `phpstorm://open?file=<path>&line=<n>` links to jump straight to the offending line. That still requires something, on the system side, to know what to do with that URL scheme: this is what this handler is for, registered with `xdg` as the default application for `phpstorm://` (plus `pstorm://` and `txmt://`, which some PHP tools emit instead).

It accepts the four shapes found in practice:

```
phpstorm://open?file=<path>&line=<n>
phpstorm://open?url=file://<path>&line=<n>
phpstorm://open?file=<path>:<n>
phpstorm://open?url=file://<path>:<n>
```

Derived from [sanduhrs/phpstorm-url-handler](https://github.com/sanduhrs/phpstorm-url-handler) (GPL), by Stefan Auditor.

## The detour through the project directory

Since **PhpStorm 2026.2**, the launcher rejects `phpstorm --line <n> <file>` with `unrecognized option: --line`: `--line` is only accepted when the *first* argument is a project directory (`phpstorm --help` gives the shape `[/project/dir|--temp-project] [--wait] [--line <line>] [--column <column>] file`).

The handler therefore walks up from the file to the nearest `.idea/` to recover the project it belongs to, then calls:

```
phpstorm <project-root> --line <n> <file>
```

If it finds no `.idea/`, it opens the file alone — without jumping to the line, since `--line` would be refused.

Once the file is open, it tries to raise the PhpStorm window with `wmctrl`. This is best-effort: it only works under X11, and failing there has no consequence on opening the file.

## Installation (home-manager)

```nix
# flake.nix
inputs.direnv-ide-shim.url = "github:umanit/direnv-ide-shim";

# home.nix
imports = [ inputs.direnv-ide-shim.homeModules.phpstorm-url-handler ];

programs.phpstorm-url-handler.enable = true;
```

The module installs the binary, declares the `.desktop` entry through `xdg.desktopEntries` and registers the MIME association.

Nothing has to refresh `mimeinfo.cache` by hand: `xdg.desktopEntries` ships the entry as a package in the profile, and `xdg.mime` (on by default on Linux) runs `update-desktop-database` over that profile's `share/applications`. That cache matters because GNOME's application chooser — which the browser's call goes through, via the xdg portal — reads it rather than `mimeapps.list`, and reports "no application available" for a scheme missing from it. The one thing to avoid, then, is setting `xdg.mime.enable = false`.

### Options

| Option | Default | Purpose |
|---|---|---|
| `programs.phpstorm-url-handler.enable` | `false` | Enables the handler. |
| `programs.phpstorm-url-handler.phpstorm` | `pkgs.jetbrains.phpstorm` | PhpStorm package whose CLI launcher is invoked. Override it when PhpStorm comes from somewhere else (an EAP build, a Toolbox install wrapped in a derivation…). |
| `programs.phpstorm-url-handler.schemes` | `[ "phpstorm" "pstorm" "txmt" ]` | URL schemes to register. |
| `programs.phpstorm-url-handler.package` | built from `phpstorm` | The handler package itself, for the cases the options above don't cover. |

### Without home-manager

```bash
nix profile install "github:umanit/direnv-ide-shim#phpstorm-url-handler"
```

The `.desktop` entry and the MIME association then have to be written by hand (see `modules/home-manager/phpstorm-url-handler.nix` for their exact contents).

## Checking

```bash
xdg-mime query default x-scheme-handler/phpstorm   # -> phpstorm-url-handler.desktop
phpstorm-url-handler "phpstorm://open?file=$PWD/some/file.php&line=10"
```

PhpStorm being proprietary, this flake explicitly allows that one unfree package (`config.allowUnfreePredicate` in `flake.nix`): without it, `nix flake check` and `nix profile install` would fail as long as `NIXPKGS_ALLOW_UNFREE` is not set.
