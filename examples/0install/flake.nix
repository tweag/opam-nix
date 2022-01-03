# Build using the compiler from opam
{
  outputs = { self, opam-nix }: {
    legacyPackages.x86_64-linux = let
      inherit (opam-nix.lib.x86_64-linux) queryToScope;
      scope = queryToScope { } {
        "0install" = null;
        # The following line forces opam to choose the compiler from opam instead of the nixpkgs one
      };
     in scope;

    defaultPackage.x86_64-linux = self.legacyPackages.x86_64-linux."0install";
  };
}
