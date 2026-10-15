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

    # Written by hand instead of via `xdg.desktopEntries`: that module is
    # broken on some home-manager releases (it always sets the removed
    # `extraConfig` option internally - https://github.com/nix-community/home-manager,
    # modules/misc/xdg-desktop-entries.nix - and errors on any entry).
    xdg.dataFile."applications/${desktopEntry}".text = ''
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=PhpStorm URL Handler
      Comment=Open phpstorm:// links in PhpStorm
      Icon=phpstorm
      NoDisplay=true
      Categories=TextEditor;Utility;
      Exec=${lib.getExe cfg.package} %u
      Terminal=false
      MimeType=${lib.concatMapStrings (scheme: "x-scheme-handler/${scheme};") cfg.schemes}
    '';

    xdg.mimeApps = {
      enable = true;
      defaultApplications = lib.genAttrs (map (scheme: "x-scheme-handler/${scheme}") cfg.schemes) (
        _: desktopEntry
      );
    };

    # mimeapps.list/xdg-mime are correct as soon as they are written, but
    # GNOME's own app-chooser (what the browser's URL-open portal call goes
    # through) reads applications/mimeinfo.cache instead, which is only ever
    # rebuilt by this command - without it, a new scheme handler silently
    # shows as "no app available" until something else happens to trigger the
    # rebuild.
    home.activation.phpstormUrlHandlerDesktopDatabase = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.desktop-file-utils}/bin/update-desktop-database $VERBOSE_ARG "${config.xdg.dataHome}/applications"
    '';
  };
}
