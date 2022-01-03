# A big, girthy application with a big dependency tree
{
  outputs = { self, opam-nix }: {
    legacyPackages.x86_64-linux = let

      inherit (opam-nix.lib.x86_64-linux) queryToScope;


      scope = queryToScope { } {
        tezos = null;
        ocaml-base-compiler = null;
      };
      overlay = self: super: { };
    in scope.overrideScope' overlay;

    defaultPackage.x86_64-linux = self.legacyPackages.x86_64-linux.tezos;
  };
}
