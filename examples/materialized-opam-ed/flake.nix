{
  description = "opam-ed, without any IFD";
  nixConfig.allow-import-from-derivation = false;
  inputs.opam-nix.url = "github:tweag/opam-nix";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs =
    {
      self,
      opam-nix,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (system: {
      legacyPackages =
        let
          inherit (opam-nix.lib.${system}) materializedDefsToScope;
          scope = materializedDefsToScope { } ./package-defs.json;
          overlay = self: super: { };
        in
        scope.overrideScope overlay;

      packages.default = self.legacyPackages.${system}.opam-ed;

      devShells.default =
        with opam-nix.inputs.nixpkgs.legacyPackages.${system};
        mkShell { buildInputs = [ opam-nix.packages.${system}.opam-nix-gen ]; };
    });
}
