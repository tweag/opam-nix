inputs: pkgs:
let
  opam-nix = inputs.self.lib.${pkgs.system};
  repos = [ inputs.opam-repository ];
  scope = opam-nix.queryToScope {
    inherit repos;
    pkgs = pkgs.pkgsStatic;
  } {
    opam-ed = null;
    ocaml-base-compiler = null;
  };
  overlay = self: super: {
    opam-ed = super.opam-ed.overrideAttrs (_: {
      postFixup = "rm -rf $out/nix-support";
    });
  };

in scope.overrideScope' overlay
