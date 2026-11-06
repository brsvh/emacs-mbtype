{
  elfmt,
  fonts,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    baseNameOf
    concatStringsSep
    getExe
    makeBinPath
    map
    removeAttrs
    ;

  inherit (lib.generators)
    toINIWithGlobalSection
    ;

  inherit (pkgs)
    writeText
    ;

  inherit (pkgs.formats)
    toml
    ;

  formatters = with pkgs; [
    elfmt
    nixfmt
  ];
in
{
  env = [
    {
      name = "FONTCONFIG_FILE";
      value = pkgs.makeFontsConf { fontDirectories = fonts; };
    }
  ];

  files = {
    editorconfig = rec {
      data = {
        root = true;

        "*" = {
          charset = "utf-8";
          end_of_line = "lf";
          indent_size = 8;
          indent_style = "tab";
          insert_final_newline = true;
          max_line_length = 70;
          tab_width = 8;
          trim_trailing_whitespace = true;
        };

        "*.el" = {
          indent_size = "unset";
          indent_style = "space";
          tab_width = 2;
        };

        "*.nix" = {
          indent_size = 2;
          indent_style = "space";
          max_line_length = 80;
          tab_width = 2;
        };

        "README" = {
          indent_size = 2;
          indent_style = "space";
          max_line_length = 80;
          trim_trailing_whitespace = false;
        };
      };

      generator =
        data:
        let
          name = baseNameOf path;

          value = {
            globalSection = {
              root = data.root or true;
            };

            sections = removeAttrs data [
              "root"
            ];
          };
        in
        writeText name (toINIWithGlobalSection { } value);

      packages = with pkgs; [
        editorconfig-checker
      ];

      path = ".editorconfig";
    };

    prek = rec {
      data = {
        default_install_hook_types = [
          "pre-commit"
        ];

        repos = [
          {
            repo = "local";

            hooks = [
              {
                entry = "treefmt --fail-on-change";
                id = "treefmt";
                language = "system";
                name = "treefmt";
                require_serial = true;

                stages = [
                  "pre-commit"
                ];
              }
            ];
          }
        ];
      };

      deps = [
        "treefmt"
      ];

      generator = data: (toml { }).generate (baseNameOf path) data;

      hook =
        let
          inherit (pkgs)
            git
            prek
            runtimeShell
            writeScript
            ;

          mkInstall = stage: ''
            if hooksDir="$(
              ${getExe git} -C "$PRJ_ROOT" \
                rev-parse --path-format=absolute --git-path hooks \
                2>/dev/null
            )"; then
              mkdir -p "$hooksDir"
              ln -sf "${mkScript stage}" "$hooksDir/${stage}"
            fi
          '';

          mkScript =
            stage:
            writeScript "prek-${stage}" ''
              #!${runtimeShell}
              if [ "''${PREK:-}" = "0" ] || [ "''${LEFTHOOK:-}" = "0" ]; then
                exit 0
              fi

              repoRoot="$(${getExe git} rev-parse --show-toplevel)" || exit 1
              export PATH=${
                makeBinPath (
                  formatters
                  ++ [
                    git
                    pkgs.treefmt
                  ]
                )
              }:"$PATH"

              gitDir="$(
                ${getExe git} -C "$repoRoot" \
                  rev-parse --absolute-git-dir \
                  2>/dev/null || true
              )"

              if [ -n "$gitDir" ]; then
                if [ -e "$gitDir/MERGE_HEAD" ] \
                  || [ -d "$gitDir/rebase-apply" ] \
                  || [ -d "$gitDir/rebase-merge" ]; then
                  exit 0
                fi
              fi

              exec ${getExe prek} -C "$repoRoot" run --stage "${stage}" "$@"
            '';
        in
        concatStringsSep "\n" (map mkInstall data.default_install_hook_types);

      packages = with pkgs; [
        git
        prek
      ];

      path = "prek.toml";
    };

    treefmt = rec {
      data = {
        formatter = {
          emacs-lisp = {
            command = "elfmt";

            includes = [
              "*.el"
            ];
          };

          nix = {
            command = "nixfmt";

            includes = [
              "*.nix"
            ];

            options = [
              "--width=80"
            ];
          };
        };
      };

      generator = data: (toml { }).generate (baseNameOf path) data;

      packages = formatters ++ [
        pkgs.treefmt
      ];

      path = "treefmt.toml";
    };
  };

  packages = with pkgs; [
    emacs
  ];
}
