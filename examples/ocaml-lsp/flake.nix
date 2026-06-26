{
  description = "Build an opam project with multiple packages";
  inputs.opam-nix.url = "github:tweag/opam-nix";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:nixos/nixpkgs";
  outputs =
    {
      self,
      nixpkgs,
      opam-nix,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (system: {
      legacyPackages =
        let
          src = nixpkgs.legacyPackages.${system}.fetchFromGitHub {
            owner = "ocaml";
            repo = "ocaml-lsp";
            rev = "b309c2e58dd0c9077271bb0204554d4694e26317";
            sha256 = "/rtKoUqaNoBcqHGZ/qwSBQKnrqo7F+kNTEsqb3ZpkJs=";
            fetchSubmodules = true;
          };
          inherit (opam-nix.lib.${system}) buildOpamProject';
          scope = buildOpamProject' { } src { ocaml-base-compiler = "*"; };
          merlinSrc = nixpkgs.legacyPackages.${system}.fetchFromGitHub {
            owner = "ocaml";
            repo = "merlin";
            rev = "03c8e3f0cef88ead9f217c35af89523eeaf095d3";
            sha256 = "sha256-QvLHseQN/KBDeAZ6Y4X1qCxx0OsoWIKVwfoZo6bLIOI=";
          };
        in
        scope.overrideScope (self: super: {
          merlin-lib = super.merlin-lib.overrideAttrs (_: { src = merlinSrc; });
        });

      packages.default = self.legacyPackages.${system}.ocaml-lsp-server;
    });
}
