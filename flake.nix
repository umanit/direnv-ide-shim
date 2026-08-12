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
          mkShim = tool: pkgs.writeShellScriptBin "ide-${tool}" ''
            set -euo pipefail
            exec ${pkgs.direnv}/bin/direnv exec "$PWD" ${tool} "$@"
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
