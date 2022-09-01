{
  description =
    "Build a package from opam-repository, linked statically (on Linux)";
  inputs.opam-nix.url = "github:tweag/opam-nix";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, opam-nix, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: {
      legacyPackages = let
        inherit (opam-nix.lib.${system}) queryToScope;
        pkgs = opam-nix.inputs.nixpkgs.legacyPackages.${system};
        scope = queryToScope { pkgs = pkgs.pkgsStatic; } {
          opam-ed = "*";
          ocaml-system = "4.12";
        };
        overlay = self: super: {
          # Prevent unnecessary dependencies on the resulting derivation
          opam-ed = super.opam-ed.overrideAttrs (_: {
            removeOcamlReferences = true;
            postFixup = "rm -rf $out/nix-support";
          });
        };
      in scope.overrideScope' overlay;
      defaultPackage = self.legacyPackages.${system}.opam-ed;
    });
}
