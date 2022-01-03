# Example of using a custom opam repository
{
  outputs = { self, opam-nix, opam2json }: {
    legacyPackages.x86_64-linux = let
      inherit (opam-nix.lib.x86_64-linux) opam-nix;
      scope = opam-nix.buildOpamProject { } opam2json { };
    in scope;
    defaultPackage.x86_64-linux = self.legacyPackages.x86_64-linux.opam2json;
  };
}
