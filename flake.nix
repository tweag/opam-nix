{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    opam2json.url = "github:tweag/opam2json";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    # Used for examples/tests and as a default repository
    opam-repository = {
      url = "github:ocaml/opam-repository";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, flake-utils, opam2json, opam-repository, ... }@inputs:
    {
      aux = import ./lib.nix nixpkgs.lib;
      templates.simple = {
        description = "Build a package from opam-repository";
        path = ./templates/simple;
      };
      templates.local = {
        description = "Build an opam package from a local directory";
        path = ./templates/local;
      };
      defaultTemplate = self.templates.local;

      overlays = {
        ocaml-overlay = import ./overlays/ocaml.nix;
        ocaml-static-overlay = import ./overlays/ocaml-static.nix;
      };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        opam-overlay = self: super: {
          opam = super.opam.overrideAttrs
            (oa: { patches = oa.patches or [ ] ++ [ ./opam.patch ]; });
        };
        pkgs = nixpkgs.legacyPackages.${system}.extend
          (nixpkgs.lib.composeManyExtensions [
            opam2json.overlay
            opam-overlay
          ]);
        opam-nix = import ./opam.nix { inherit pkgs opam-repository; };
      in rec {
        lib = opam-nix;
        checks = packages
          // (pkgs.callPackage ./examples/readme { inherit opam-nix; });

        packages = let
          examples = rec {
            _0install = (import ./examples/0install/flake.nix).outputs {
              self = _0install;
              opam-nix = inputs.self;
              inherit (inputs) flake-utils;
            };
            frama-c = (import ./examples/frama-c/flake.nix).outputs {
              self = frama-c;
              opam-nix = inputs.self;
            };
            opam-ed = (import ./examples/frama-c/flake.nix).outputs {
              self = opam-ed;
              opam-nix = inputs.self;
            };
            opam2json = (import ./examples/opam2json/flake.nix).outputs {
              self = opam2json;
              opam-nix = inputs.self;
              inherit (inputs) opam2json;
            };
            opam2json-static =
              (import ./examples/opam2json-static/flake.nix).outputs {
                self = opam2json-static;
                opam-nix = inputs.self;
                inherit (inputs) opam2json;
              };
            tezos = (import ./examples/tezos/flake.nix).outputs {
              self = tezos;
              opam-nix = inputs.self;
            };
          };
        in builtins.mapAttrs (_: e: e.defaultPackage.${system}) examples;
      });
}
