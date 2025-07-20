{
  description = "Build an opam project not in the repo, using sane defaults";
  inputs.opam-nix.url = "github:tweag/opam-nix";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.opam2json.url = "github:tweag/opam2json";
  outputs =
    {
      self,
      opam-nix,
      opam2json,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (system: {
      legacyPackages =
        let
          inherit (opam-nix.lib.${system}) buildOpamProject;
          scope = buildOpamProject { } "opam2json" opam2json {
            ocaml-system = "*";
          };
        in
        scope;

      packages.default = self.legacyPackages.${system}.opam2json;
    });
}
