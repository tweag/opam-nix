# We can build GUI stuff!
# Don't try to build it statically though
{
  inputs.opam-nix.url = "github:tweag/opam-nix";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, opam-nix, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: {
      legacyPackages = let
        inherit (opam-nix.lib.${system}) queryToScope;

        pkgs = opam-nix.inputs.nixpkgs.legacyPackages.${system};

        pkgs' = if pkgs.stdenv.isDarwin then pkgs else pkgs.pkgsStatic;

        scope = queryToScope { } {
          frama-c = null;
          lablgtk3 = null;
          lablgtk3-sourceview3 = null;
          conf-gtksourceview = null;
          ocaml-base-compiler = "4.12.0";
        };

        overlay = self: super: {
          # opam is adamant about using gtk2 :/
          lablgtk = null;

          frama-c = super.frama-c.overrideAttrs (oa: {
            nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.makeWrapper ];

            NIX_LDFLAGS = with pkgs;
              "-L${pkgs'.fontconfig.lib}/lib -L${pkgs'.pkgsStatic.expat}/lib -lfontconfig -lfreetype -lexpat";
            postInstall = ''
              for i in $(find $out/bin -type f); do
                wrapProgram "$i" --prefix OCAMLPATH : "$OCAMLPATH"
              done
            '';
          });
        };

      in scope.overrideScope' overlay;

      defaultPackage = self.legacyPackages.${system}.frama-c;
    });
}
