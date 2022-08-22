{
  description = "Build an opam project with multiple packages";
  inputs.opam-nix.url = "github:tweag/opam-nix";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:nixos/nixpkgs";
  outputs = { self, nixpkgs, opam-nix, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: {
      legacyPackages = let
        src = nixpkgs.legacyPackages.${system}.fetchFromGitHub {
          owner = "ocaml";
          repo = "ocaml-lsp";
          rev = "c961c46fc4705b18d336ac990b9c3b39354b9d7b";
          sha256 = "U7g2ilKfd8EES1EDgy46LKkG/z1jwpd5LIkkqhe13iI=";
          fetchSubmodules = true;
        };
        inherit (opam-nix.lib.${system}) buildOpamProject';
        scope = buildOpamProject' { } src { };
      in scope;
      defaultPackage = self.legacyPackages.${system}.ocaml-lsp-server;
    });
}
