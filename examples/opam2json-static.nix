inputs: pkgs:
let
  opam-nix = inputs.self.lib.${pkgs.system};
  repos = [ (opam-nix.makeOpamRepo inputs.opam2json) inputs.opam-repository ];
  scope = opam-nix.queryToScope {
    inherit repos;
    pkgs = pkgs.pkgsStatic;
    buildPackages = pkgs;
  } {
    opam2json = null;
    ocaml = "4.11.1";
  };
  overlay = self: super: {
    opam-file-format = super.opam-file-format.overrideAttrs
      (_: { buildPhase = "make opam-file-format.cma opam-file-format.cmxa"; });
  };

in scope.overrideScope' overlay
