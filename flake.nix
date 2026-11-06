{
  description = "Typography for Emacs";

  inputs = {
    flake-parts = {
      inputs = {
        nixpkgs-lib = {
          follows = "nixpkgs";
        };
      };

      url = "git+https://github.com/hercules-ci/flake-parts.git?ref=main";
    };

    nixpkgs = {
      url = "git+https://github.com/NixOS/nixpkgs.git?ref=nixpkgs-unstable";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      self,
      ...
    }:
    let
      inherit (flake-parts.lib)
        mkFlake
        ;

      projectRoot = ./.;
    in
    mkFlake
      {
        inherit
          inputs
          ;

        specialArgs = {
          inherit
            projectRoot
            ;
        };
      }
      {
        imports = [
          flake-parts.flakeModules.partitions
        ];

        flake = {
          overlays = {
            default =
              _: prev:
              let
                inherit (prev)
                  emacsPackagesFor
                  ;

                emacs-mbtype =
                  {
                    lib,
                    melpaBuild,
                    ...
                  }:
                  let
                    inherit (lib)
                      licenses
                      maintainers
                      ;
                  in
                  melpaBuild {
                    files = ''("mbtype.el")'';

                    meta = {
                      description = "Typography for Emacs";
                      homepage = "https://github.com/brsvh/emacs-mbtype";
                      license = licenses.gpl3Plus;
                      maintainers = with maintainers; [ brsvh ];
                    };

                    pname = "mbtype";
                    src = projectRoot + /src;
                    version = "0.1.0";
                  };

                scope = finalAttrs: _: {
                  mbtype = finalAttrs.callPackage emacs-mbtype { };
                };
              in
              {
                emacsPackagesFor = emacs: (emacsPackagesFor emacs).overrideScope scope;
              };
          };
        };

        partitionedAttrs = {
          devShells = "tool";
          formatter = "tool";
        };

        partitions = {
          tool = {
            extraInputsFlake = projectRoot + /tool;

            module =
              {
                ...
              }:
              {
                imports = [
                  (projectRoot + /tool/flake-module.nix)
                ];
              };
          };
        };

        perSystem =
          {
            lib,
            pkgs,
            system,
            ...
          }:
          let
            inherit (lib)
              getExe
              ;

            emacsPackages = pkgs.emacsPackagesFor pkgs.emacs;

            emacs = emacsPackages.emacsWithPackages (epkgs: [
              epkgs.mbtype
            ]);
          in
          {
            _module = {
              args = {
                pkgs = import nixpkgs {
                  inherit
                    system
                    ;

                  overlays = [
                    self.overlays.default
                  ];
                };
              };
            };

            apps = {
              default = {
                type = "app";

                program = getExe (
                  pkgs.writeShellScriptBin "emacs-mbtype" ''
                    # Make the packaged libraries available with -Q.
                    exec ${getExe emacs} \
                      --load ${emacs.deps}/share/emacs/site-lisp/subdirs.el \
                      "$@"
                  ''
                );
              };
            };

            packages = rec {
              default = mbtype;
              mbtype = emacsPackages.mbtype;
            };
          };

        systems = [
          "x86_64-linux"
        ];
      };
}
