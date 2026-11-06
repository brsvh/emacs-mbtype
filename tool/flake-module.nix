{
  inputs,
  ...
}:
let
  inherit (inputs)
    chinese-fonts-overlay
    elfmt
    infix
    nixpkgs
    ;
in
{
  imports = [
    infix.flakeModules.devshell
  ];

  perSystem =
    {
      config,
      lib,
      pkgs,
      system,
      ...
    }:
    let
      inherit (lib)
        getName
        ;

      fontPkgs = import nixpkgs {
        inherit
          system
          ;

        config = {
          allowUnfreePredicate = pkg: getName pkg == "tsangertype-tsangerxuansan";
        };

        overlays = [
          chinese-fonts-overlay.overlays.default
        ];
      };
    in
    {
      devshells = {
        default = import ./devshells/default.nix {
          inherit
            lib
            pkgs
            ;

          elfmt = elfmt.packages.${system}.elfmt;

          fonts = with fontPkgs; [
            lxgw-wenkai
            lxgwPackages.neo-zhisong
            tsangertypePackages.tsangerxuansan
          ];
        };
      };

      formatter = import ./formatter.nix {
        inherit
          lib
          pkgs
          ;

        treefmtConfig = config.devshells.default.files.treefmt;
      };
    };
}
