# CLAUDE.md

Glue between PhpStorm and Nix/direnv PHP projects. Two unrelated tools share
this repo: the `php`/`composer` shims, and `phpstorm-url-handler`. See
README.md for what they do and why.

## Layout

```
flake.nix                                     assembly point only — no logic here
pkgs/direnv-ide-shim.nix                      the shims
pkgs/phpstorm-url-handler.nix                 the phpstorm:// handler
modules/home-manager/phpstorm-url-handler.nix programs.phpstorm-url-handler
checks/                                       one file per check in `nix flake check`
```

Logic belongs in `pkgs/` or `modules/`, never in `flake.nix`.

## Commands

```bash
nix flake check -L     # evaluates every output, builds and runs every check
nix fmt                # nixfmt via treefmt; run before committing
nix build .#direnv-ide-shim
nix build .#checks.x86_64-linux.handler-parsing -L   # one check, with output
```

`nix build .#phpstorm-url-handler` pulls in PhpStorm — about 1.5 GB of unfree
IDE. Avoid it unless the point really is the real binary; `nix flake check`
only *evaluates* that package, and the checks swap in a stub.

## Things that will bite you

**PhpStorm is unfree.** `flake.nix` imports nixpkgs with an
`allowUnfreePredicate` restricted to `phpstorm`, so `nix flake check` and
`nix profile install` work without `NIXPKGS_ALLOW_UNFREE`. Keep that predicate
narrow — it exists for that one package.

**`--line` needs a project directory first.** Since PhpStorm 2026.2,
`phpstorm --line <n> <file>` is rejected with `unrecognized option: --line`;
the option is only accepted when the first argument is a project directory.
The handler walks up to the nearest `.idea/` for that reason. Do not "simplify"
it back.

**Checks run under stdenv's errexit.** A check that deliberately runs a failing
command, then inspects its status, must `set +e` first — otherwise the builder
dies at the first failure, and the log looks mysteriously empty.

**Two shims on one PATH loop forever.** The shim re-execs the next same-named
binary on PATH that is not itself. Two *different* store paths of the shim both
on PATH (an old profile plus a fresh build, say) each see the other as "not
itself" and hand off in circles. That bites when testing by hand on a machine
where the shim is already installed, not in the sandbox.

**The handler's script is a `writeShellApplication`**, so shellcheck runs at
build time and the script runs under `set -euo pipefail`. A command allowed to
fail needs an explicit `|| true` — that is why the `wmctrl` part has one.

## Conventions

- Everything in this repo is in English: code, comments, README, commit
  messages. Conversation with the user may be in French; the repo is not.
- Comments explain *why*, not what the line does. Most comments here record a
  constraint discovered the hard way (an upstream bug, a shell gotcha); keep
  that shape, and name the constraint.
- Conventional commits (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`), with
  a body explaining the reasoning whenever the change is not obvious.
- Nix formatting is `nixfmt` through `nix fmt`. CI fails on unformatted files.

## Adding a check

Drop a file in `checks/`, add it to `checks` in `flake.nix`. A check is a
derivation that builds iff the checks pass, so it ends with `touch $out`.
Count failures rather than exiting on the first one — seeing every failure in
a single run beats discovering them one rebuild at a time.

Use a stub for anything heavy or unfree: the handler takes its `phpstorm` as
an argument precisely so a check can pass a `writeShellScriptBin` that prints
its arguments. A check that needs the home-manager module evaluated goes
through `home-manager.lib.homeManagerConfiguration` — that input exists only
for the checks.
