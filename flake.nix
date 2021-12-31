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
        checks = import ./examples inputs pkgs;
      });
}
