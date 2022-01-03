# Static build using the compiler from OPAM
{
  outputs = { self, opam-nix, opam2json }: {
    legacyPackages.x86_64-linux = let
      inherit (opam-nix.lib.x86_64-linux) buildOpamProject;
      pkgs = opam-nix.inputs.nixpkgs.legacyPackages.x86_64-linux;
      scope = buildOpamProject { pkgs = pkgs.pkgsStatic; } opam2json {
        ocaml-base-compiler =
          null; # This makes opam choose the non-system compiler
      };
      overlay = self: super: {
        # Prevent unnecessary dependencies on the resulting derivation
        opam2json = super.opam2json.overrideAttrs
          (_: { postFixup = "rm -rf $out/nix-support"; });
      };

    in scope.overrideScope' overlay;
  };
}
