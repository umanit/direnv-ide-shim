{
  description = "Binaires shim (php, composer, …) qui délèguent à `direnv exec` dans le projet courant — chemin stable pour les IDE (PhpStorm) qui n'aiment pas les chemins /nix/store qui changent à chaque rebuild.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      tools = [ "php" "composer" ];
    in {
      packages = nixpkgs.lib.genAttrs systems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          # Named after the real tool (not "ide-<tool>"): PhpStorm's Quality
          # Tools (PHPStan, PHP_CodeSniffer…) don't invoke the configured CLI
          # interpreter — they run the vendor/bin/* script directly, relying
          # on its `#!/usr/bin/env php` shebang, which needs a literal `php`
          # on PATH.
          #
          # Outside any direnv project (no .envrc found), `direnv exec` is a
          # passthrough that leaves PATH untouched, so a second, unguarded
          # lookup of the tool name would just find this same script again —
          # the guard breaks that loop. Once guarded, fall back to any *other*
          # same-named executable already on PATH (e.g. a real system-wide
          # install on a non-NixOS machine) before giving up: this one script
          # behaves correctly whether or not the machine has such a fallback,
          # with no need to special-case NixOS vs. other distros at build time
          # — `nix profile install` produces the exact same derivation either
          # way, only what's actually on PATH at runtime differs.
          mkShim = tool: pkgs.writeShellScriptBin tool ''
            set -euo pipefail

            if [ -z "''${DIRENV_IDE_SHIM_GUARD:-}" ]; then
              export DIRENV_IDE_SHIM_GUARD=1
              exec ${pkgs.direnv}/bin/direnv exec "$PWD" ${tool} "$@"
            fi

            self_real="$(readlink -f "$0")"
            IFS=':' read -ra dirs <<< "$PATH"
            for dir in "''${dirs[@]}"; do
              candidate="$dir/${tool}"
              if [ -x "$candidate" ] && [ "$(readlink -f "$candidate")" != "$self_real" ]; then
                exec "$candidate" "$@"
              fi
            done

            echo "${tool}: aucun binaire ${tool} disponible pour $PWD (pas de devShell direnv actif ici, ni ailleurs sur le PATH)" >&2
            exit 127
          '';
        in {
          default = pkgs.symlinkJoin {
            name = "direnv-ide-shim";
            paths = map mkShim tools;
          };
        }
      );
    };
}
