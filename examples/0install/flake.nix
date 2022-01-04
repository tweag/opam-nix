{
  description = "Build a package from opam-repository, using the non-system compiler";
  inputs.opam-nix.url = "github:tweag/opam-nix";
  outputs = { self, opam-nix }: {
    legacyPackages.x86_64-linux = let
      inherit (opam-nix.lib.x86_64-linux) queryToScope;
      scope = queryToScope { } {
        "0install" = null;
        # The following line forces opam to choose the compiler from opam instead of the nixpkgs one
        ocaml-base-compiler = null;
      };
    in scope;

    defaultPackage.x86_64-linux = self.legacyPackages.x86_64-linux."0install";
  };
}
