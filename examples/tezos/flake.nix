{
  description = "Big, girthy package with a lot of dependencies";
  inputs.opam-nix.url = "github:tweag/opam-nix";
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
