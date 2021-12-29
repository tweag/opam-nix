# Static build using the compiler from OPAM
inputs: pkgs:
let
  opam-nix = inputs.self.lib.${pkgs.system};
  repos = [ (opam-nix.makeOpamRepo inputs.opam2json) inputs.opam-repository ];
  scope = opam-nix.queryToScope {
    inherit repos;
    pkgs = pkgs.pkgsStatic;
  } {
    opam2json = null;
    ocaml-base-compiler = null; # This makes opam choose the non-system compiler
  };
  overlay = self: super: {
    # Prevent unnecessary dependencies on the resulting derivation
    opam2json = super.opam2json.overrideAttrs (_: {
      postFixup = "rm -rf $out/nix-support";
    });
  };

in scope.overrideScope' overlay
