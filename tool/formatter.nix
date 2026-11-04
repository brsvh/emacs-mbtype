{
  lib,
  pkgs,
  treefmtConfig,
}:
let
  inherit (lib)
    makeBinPath
    ;

  inherit (pkgs)
    git
    treefmt
    writeShellScriptBin
    ;

  inherit (treefmtConfig)
    file
    packages
    ;
in
writeShellScriptBin "treefmt" ''
  set -euo pipefail

  export PATH=${makeBinPath (packages ++ [ git ])}

  exec ${treefmt}/bin/treefmt \
    --config-file=${file} \
    --no-cache \
    --tree-root-file=flake.nix \
    --walk=git \
    "$@"
''
