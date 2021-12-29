{
  inputs = { opam-nix.url = "github:tweag/opam-nix"; };
  outputs = { self, nixpkgs, opam-nix }: {
    legacyPackages.x86_64-linux = let
      scope = opam-nix.lib.x86_64-linux.queryToScope { } {
        # Put the name of the package here
        opam-ed = null;
        # Comment next line if you want to use the compiler provided by nixpkgs
        ocaml-base-compiler =
          "4.12.0"; # Change the version here if you want a different ocaml version
      };
      overlay = self: super:
        {
          # Your overrides go here
        };
    in scope.overrideScope' overlay;

    defaultPackage.x86_64-linux =
      self.legacyPackages.x86_64-linux.opam-ed; # Also put the package name here
  };
}
