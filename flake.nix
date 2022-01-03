{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    opam2json.url= "github:tweag/opam2json";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    # Used for examples/tests and as a default repository
    opam-repository = {
      url = "github:ocaml/opam-repository";
      flake = false;
    };

    # Examples
    "0install" = {
      url = "./examples/0install";
      inputs.opam-nix.follows = "";
    };
    "frama-c" = {
      url = "./examples/frama-c";
      inputs.opam-nix.follows = "";
    };
    "opam2json-example" = {
      url = "./examples/opam2json";
      inputs.opam2json.follows = "opam2json";
      inputs.opam-nix.follows = "";
    };
    "opam2json-example-static" = {
      url = "./examples/opam2json-static";
      inputs.opam2json.follows = "opam2json";
      inputs.opam-nix.follows = "";
    };
    "opam-ed" = {
      url = "./examples/opam-ed";
      inputs.opam-nix.follows = "";
    };
    "tezos" = {
      url = "./examples/tezos";
      inputs.opam-nix.follows = "";
    };
  };

  outputs = { self, nixpkgs, flake-utils, opam2json, opam-repository, ... }@inputs:
    {
      aux = import ./lib.nix nixpkgs.lib;
      templates.simple.path = ./templates/simple;
      templates.local.path = ./templates/local;
      defaultTemplate = self.templates.local;
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system}.extend opam2json.overlay;
        opam-nix = import ./opam.nix { inherit pkgs opam-repository; };
      in rec {
        lib = opam-nix;

        overlays = {
          ocaml-overlay = import ./overlays/ocaml.nix;
          ocaml-static-overlay = import ./overlays/ocaml-static.nix;
        };

        packages = checks;

        checks."0install" = inputs."0install".defaultPackage.${system};
        checks.frama-c = inputs.frama-c.defaultPackage.${system};
        checks.opam-ed = inputs.opam-ed.defaultPackage.${system};
        checks.opam2json = inputs.opam2json-example.defaultPackage.${system};
        checks.opam2json-static = inputs.opam2json-example-static.defaultPackage.${system};
        checks.tezos = inputs.tezos.defaultPackage.${system};
      });
}
