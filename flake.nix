{
  description = "A Nix-flake-based Typst development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.pre-commit-hooks.flakeModule
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      perSystem =
        {
          config,
          pkgs,
          ...
        }:
        {
          # https://flake.parts/options/treefmt-nix.html
          # Example: https://github.com/nix-community/buildbot-nix/blob/main/nix/treefmt/flake-module.nix
          treefmt = {
            projectRootFile = "flake.nix";
            settings.global.excludes = [ ];

            programs = {
              autocorrect.enable = true;
              nixfmt.enable = true;
              typstyle.enable = true;
            };
          };

          # https://flake.parts/options/git-hooks-nix.html
          # Example: https://github.com/cachix/git-hooks.nix/blob/master/template/flake.nix
          pre-commit.settings.package = pkgs.prek;
          pre-commit.settings.configPath = ".pre-commit-config.flake.yaml";
          pre-commit.settings.excludes = [ "^(.*[.]png)$" ];
          pre-commit.settings.hooks = {
            eclint.enable = true;
            treefmt.enable = true;
          };

          devShells.default = pkgs.mkShellNoCC {
            strictDeps = true;
            __structuralAttrs = true;

            inputsFrom = [
              config.treefmt.build.devShell
              config.pre-commit.devShell
            ];

            nativeBuildInputs = with pkgs; [
              typst
              tinymist
              pandoc
            ];

            shellHook = ''
              export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct 2>/dev/null || date +%s)
              echo 1>&2 "Welcome to the development shell!"
            '';
          };
        };
    };
}
