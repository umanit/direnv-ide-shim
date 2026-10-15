{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.phpstorm-url-handler;
  desktopEntry = "phpstorm-url-handler.desktop";
in
{
  options.programs.phpstorm-url-handler = {
    enable = lib.mkEnableOption ''
      the phpstorm:// URL scheme handler, so that links from the Symfony
      profiler, Whoops and friends open the file in a running PhpStorm
    '';

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../pkgs/phpstorm-url-handler.nix {
        inherit (cfg) phpstorm;
      };
      defaultText = lib.literalMD "the handler from this flake, calling {option}`programs.phpstorm-url-handler.phpstorm`";
      description = "Package providing the `phpstorm-url-handler` executable.";
    };

    phpstorm = lib.mkOption {
      type = lib.types.package;
      default = pkgs.jetbrains.phpstorm;
      defaultText = lib.literalExpression "pkgs.jetbrains.phpstorm";
      description = ''
        PhpStorm package whose CLI launcher the handler invokes. Override it
        when PhpStorm comes from somewhere else than nixpkgs (a Toolbox
        install wrapped in a derivation, an EAP build…).
      '';
    };

    schemes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "phpstorm"
        "pstorm"
        "txmt"
      ];
      example = [ "phpstorm" ];
      description = ''
        URL schemes to register the handler for. `txmt` (TextMate) is in the
        default set because several PHP tools emit it as their editor link.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # `xdg.desktopEntries` installs the entry as a package into the profile
    # rather than writing it under xdg.dataHome. That is what makes the
    # mimeinfo.cache refresh unnecessary here: `xdg.mime` (on by default on
    # Linux) runs update-desktop-database over the profile's share/applications
    # from home.extraProfileCommands. Without that cache, GNOME's app-chooser -
    # which the browser's URL-open portal call goes through, and which reads
    # mimeinfo.cache rather than mimeapps.list - reports a freshly declared
    # scheme as "no app available".
    xdg.desktopEntries.phpstorm-url-handler = {
      name = "PhpStorm URL Handler";
      comment = "Open phpstorm:// links in PhpStorm";
      icon = "phpstorm";
      exec = "${lib.getExe cfg.package} %u";
      terminal = false;
      noDisplay = true;
      categories = [
        "Utility"
        "TextEditor"
      ];
      mimeType = map (scheme: "x-scheme-handler/${scheme}") cfg.schemes;
    };

    xdg.mimeApps = {
      enable = true;
      defaultApplications = lib.genAttrs (map (scheme: "x-scheme-handler/${scheme}") cfg.schemes) (
        _: desktopEntry
      );
    };
  };
}
