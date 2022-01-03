# Static build using the compiler from nixpkgs
{
  outputs = { self, opam-nix }: {
    legacyPackages.x86_64-linux = let
      inherit (opam-nix.lib.x86_64-linux) queryToScope;
      pkgs = opam-nix.inputs.legacyPackages.x86_64-linux;
      scope = queryToScope { pkgs = pkgs.pkgsStatic; } {
        opam-ed = null;
        ocaml-system = null;
      };
      overlay = self: super: {
        # Prevent unnecessary dependencies on the resulting derivation
        opam-ed = super.opam-ed.overrideAttrs
          (_: { postFixup = "rm -rf $out/nix-support"; });
      };
    in scope.overrideScope' overlay;
    defaultPackage.x86_64-linux = self.legacyPackages.x86_64-linux.opam-ed;
  };
}
