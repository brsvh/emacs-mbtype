{
  inputs,
  ...
}:
let
  inherit (inputs)
    elfmt
    infix
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
    {
      devshells = {
        default = import ./devshells/default.nix {
          inherit
            lib
            pkgs
            ;

          elfmt = elfmt.packages.${system}.elfmt;
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
