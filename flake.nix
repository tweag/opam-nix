{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    opam2json = {
      url = "github:tweag/opam2json";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    # Used for examples/tests and as a default repository
    opam-repository = {
      url = "github:ocaml/opam-repository";
      flake = false;
    };

    # used for opam-monorepo
    opam-overlays = {
      url = "github:dune-universe/opam-overlays";
      flake = false;
    };
    mirage-opam-overlays = {
      url = "github:dune-universe/mirage-opam-overlays";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      opam2json,
      opam-repository,
      opam-overlays,
      mirage-opam-overlays,
      ...
    }@inputs:
    {
      aux = import ./src/lib.nix nixpkgs.lib;
      templates.simple = {
        description = "Simply build an opam package, preferrably a library, from a local directory";
        path = ./templates/simple;
      };
      templates.executable = {
        description = "Build an executable from a local opam package, and provide a development shell with some convinient tooling";
        path = ./templates/executable;
      };
      templates.multi-package = {
        description = "Build multiple packages from a single workspace, and provide a development shell with some convinient tooling";
        path = ./templates/multi-package;
      };
      templates.default = self.templates.simple;

      overlays = {
        ocaml-overlay = import ./src/overlays/ocaml.nix;
        ocaml-static-overlay = import ./src/overlays/ocaml-static.nix;
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        # The formats of opam2json output that we support
        opam2json-versions = [ "0.4" ];
        pkgs = nixpkgs.legacyPackages.${system}.extend (
          nixpkgs.lib.composeManyExtensions [
            (final: prev: {
              opam2json =
                if __elem (prev.opam2json.version or null) opam2json-versions then
                  prev.opam2json
                else
                  (opam2json.overlay final prev).opam2json;
            })
          ]
        );
        opam-nix = import ./src/opam.nix {
          inherit
            pkgs
            opam-repository
            opam-overlays
            mirage-opam-overlays
            ;
        };
      in
      rec {
        lib = opam-nix;
        checks = packages // (pkgs.callPackage ./examples/docfile { inherit opam-nix; }).checks;

        legacyPackages = __mapAttrs (
          name: versions:
          let
            allVersions = __listToAttrs (
              map (
                version:
                nixpkgs.lib.nameValuePair version
                  (lib.queryToScope { } (
                    {
                      ocaml-base-compiler = "*";
                    }
                    // {
                      ${name} = version;
                    }
                  )).${name}
              ) versions
            );
          in
          allVersions
          // {
            latest = allVersions.${nixpkgs.lib.last versions};
          }
        ) (lib.listRepo opam-repository);

        allChecks = pkgs.runCommand "opam-nix-checks" { checks = __attrValues checks; } "touch $out";

        packages =
          let
            examples = rec {
              _0install = (import ./examples/0install/flake.nix).outputs {
                self = _0install;
                opam-nix = inputs.self;
                inherit (inputs) flake-utils;
              };
              rocq = (import ./examples/rocq/flake.nix).outputs {
                self = rocq;
                opam-nix = inputs.self;
                inherit (inputs) nixpkgs opam-repository flake-utils;
              };
              frama-c = (import ./examples/frama-c/flake.nix).outputs {
                self = frama-c;
                opam-nix = inputs.self;
                inherit (inputs) flake-utils;
              };
              opam-ed = (import ./examples/opam-ed/flake.nix).outputs {
                self = opam-ed;
                opam-nix = inputs.self;
                inherit (inputs) flake-utils;
              };
              opam2json = (import ./examples/opam2json/flake.nix).outputs {
                self = opam2json;
                opam-nix = inputs.self;
                inherit (inputs) opam2json flake-utils;
              };
              ocaml-lsp = (import ./examples/ocaml-lsp/flake.nix).outputs {
                self = ocaml-lsp;
                opam-nix = inputs.self;
                inherit (inputs) nixpkgs flake-utils;
              };
              opam2json-static = (import ./examples/opam2json-static/flake.nix).outputs {
                self = opam2json-static;
                opam-nix = inputs.self;
                inherit (inputs) opam2json flake-utils;
              };
              tezos = (import ./examples/tezos/flake.nix).outputs {
                self = tezos;
                opam-nix = inputs.self;
                inherit (inputs) flake-utils;
              };
              materialized-opam-ed = (import ./examples/materialized-opam-ed/flake.nix).outputs {
                self = materialized-opam-ed;
                opam-nix = inputs.self;
                inherit (inputs) flake-utils;
              };
            };
          in
          {
            opam-nix-gen = pkgs.substitute {
              name = "opam-nix-gen";
              src = ./scripts/opam-nix-gen.in;
              dir = "bin";
              isExecutable = true;

              substitutions = [
                "--subst-var-by" "runtimeShell" pkgs.runtimeShell
                "--subst-var-by" "coreutils" pkgs.nix
                "--subst-var-by" "nix" pkgs.nix
                "--subst-var-by" "opamNix" "${self}"
              ];
            };
            opam-nix-regen = pkgs.substitute {
              name = "opam-nix-regen";
              src = ./scripts/opam-nix-regen.in;
              dir = "bin";
              isExecutable = true;

              substitutions = [
                "--subst-var-by" "runtimeShell" pkgs.runtimeShell
                "--subst-var-by" "jq" pkgs.jq
                "--subst-var-by" "opamNixGen" "${self.packages.${system}.opam-nix-gen}/bin/opam-nix-gen"
              ];
            };
          }
          // builtins.mapAttrs (_: e: e.defaultPackage.${system}) examples;
      }
    );
}
