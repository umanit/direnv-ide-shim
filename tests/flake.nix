{
  description = "Checks that need home-manager, kept out of the root flake so that nothing consuming it inherits a home-manager input it will never evaluate.";

  inputs = {
    # Unlocked on purpose: a `path:` input carries no narHash, so these checks
    # always run against the working tree, with no relock step after an edit.
    root.url = "path:..";
    nixpkgs.follows = "root/nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      root,
      nixpkgs,
      home-manager,
    }:
    let
      # The module targets Linux desktops; nothing here runs on Darwin.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      checks = forAllSystems (pkgs: {
        hm-module = pkgs.callPackage ./hm-module.nix {
          inherit home-manager;
          module = root.homeModules.phpstorm-url-handler;
        };
      });
    };
}
