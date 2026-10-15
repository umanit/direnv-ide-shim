{
  description = "PhpStorm/Nix glue: shim binaries (php, composer, …) that delegate to `direnv exec` in the current project, plus a handler for phpstorm:// links.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Test-only: the checks assert what the home-manager module produces, not
    # merely that it evaluates. Nothing this flake exports depends on it.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
    let
      # x86_64-darwin is gone: nixpkgs unstable refuses to evaluate for it
      # since 26.11.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # PhpStorm is unfree, so `legacyPackages` would make every output of this
      # flake unevaluable without NIXPKGS_ALLOW_UNFREE - including `nix flake
      # check` and `nix profile install`. A flake whose whole reason to exist is
      # PhpStorm can reasonably allow that one package, and nothing else.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "phpstorm";
        };

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (pkgsFor system));
    in
    {
      packages = forAllSystems (
        pkgs:
        {
          default = pkgs.callPackage ./pkgs/direnv-ide-shim.nix { };

          direnv-ide-shim = pkgs.callPackage ./pkgs/direnv-ide-shim.nix { };
        }
        # Drives a desktop IDE through xdg scheme handlers, and PhpStorm itself
        # is Linux/Darwin-but-not-really here: keep it off platforms where it
        # cannot work rather than exposing an output that always fails.
        // nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          phpstorm-url-handler = pkgs.callPackage ./pkgs/phpstorm-url-handler.nix { };
        }
      );

      homeModules = {
        default = self.homeModules.phpstorm-url-handler;
        phpstorm-url-handler = ./modules/home-manager/phpstorm-url-handler.nix;
      };

      checks = forAllSystems (
        pkgs:
        {
          shim-fallback = pkgs.callPackage ./checks/shim-fallback.nix { };
        }
        // nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          handler-parsing = pkgs.callPackage ./checks/handler-parsing.nix { };
          hm-module = pkgs.callPackage ./checks/hm-module.nix { inherit home-manager; };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
