# Static build using the compiler from OPAM
{
  inputs.opam-nix.url = "github:tweag/opam-nix";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.opam2json.url = "github:tweag/opam2json";
  outputs = { self, opam-nix, opam2json, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: {
      legacyPackages = let
        inherit (opam-nix.lib.${system}) buildOpamProject;
        pkgs = opam-nix.inputs.nixpkgs.legacyPackages.${system};
        scope =
          buildOpamProject { pkgs = pkgs.pkgsStatic; } "opam2json" opam2json {
            ocaml-base-compiler =
              null; # This makes opam choose the non-system compiler
          };
        overlay = self: super: {
          # Prevent unnecessary dependencies on the resulting derivation
          opam2json = super.opam2json.overrideAttrs (_: {
            removeOcamlReferences = true;
            postFixup = "rm -rf $out/nix-support";
          });
        };

      in scope.overrideScope' overlay;

      defaultPackage = self.legacyPackages.${system}.opam2json;
    });
}
