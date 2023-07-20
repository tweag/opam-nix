{
  description = "Build a coq package";
  inputs.opam-nix.url = "github:tweag/opam-nix";
  inputs.opam-repository.url = "github:ocaml/opam-repository";
  inputs.nixpkgs.url = "github:nixos/nixpkgs";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, opam-nix, flake-utils, opam-repository, nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system: {
      legacyPackages = let
        pkgs = nixpkgs.legacyPackages.${system};
        opam-coq-archive = pkgs.fetchFromGitHub {
          owner = "coq";
          repo = "opam-coq-archive";
          rev = "e73f7a6f58f02a6798f31d6e77caad21e8127789";
          sha256 = "nfrHmjF84K4/Js96U7MNNaqW8TfkEmrOePH3SNPlMiw=";
        };
        inherit (opam-nix.lib.${system}) queryToScope;
        scope = queryToScope {
          repos =
            [ "${opam-repository}" "${opam-coq-archive}/extra-dev" ];
        } {
          coq = "*";
          coq-inf-seq-ext = "*";
          ocaml-base-compiler = "*";
        };
      in scope;

      defaultPackage = self.legacyPackages.${system}."coq-inf-seq-ext";
    });
}
