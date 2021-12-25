{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    opam2json = {
      url = "github:tweag/opam2json";
      flake = false;
    };
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    # Used for examples/tests
    opam-repository = {
      url = "github:ocaml/opam-repository";
      flake = false;
    };
    tezos = {
      url = "gitlab:tezos/tezos";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, ... }@inputs:
    { aux = import ./lib.nix nixpkgs.lib; } //
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        opam-nix = import ./opam.nix inputs pkgs;
      in rec {
        lib = opam-nix;

        packages = checks;
        checks = import ./examples inputs pkgs;
      });
}
