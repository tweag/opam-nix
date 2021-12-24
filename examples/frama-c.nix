inputs:
pkgs:
let
  opam-nix = inputs.self.lib.${pkgs.system};

  repos = {
    default = inputs.opam-repository;
  };
  scope = opam-nix.queryToScope { inherit repos pkgs; } {
    frama-c = null;
    lablgtk3 = null;
    ocaml = "4.12.1";
  };

  overlay = self: super: {
    frama-c = super.frama-c.overrideAttrs (oa: {
      nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.makeWrapper ];

      NIX_LDFLAGS = with pkgs; "-L${pkgs.pkgsStatic.fontconfig.lib}/lib -L${pkgs.pkgsStatic.expat}/lib -lfontconfig -lfreetype -lexpat";
      postInstall = ''
        for i in $(find $out/bin -type f); do
          wrapProgram "$i" --prefix OCAMLPATH : "$OCAMLPATH"
        done
      '';
    });
  };

in scope.overrideScope' overlay
