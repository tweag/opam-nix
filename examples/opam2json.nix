inputs: pkgs:
let
  opam-nix = inputs.self.lib.${pkgs.system};
  repos = [ (opam-nix.makeOpamRepo inputs.opam2json) inputs.opam-repository ];
  scope = opam-nix.queryToScope { inherit repos pkgs; } {
    opam2json = null;
    ocaml-base-compiler = "4.11.2";
  };
  overlay = self: super: { };

in scope.overrideScope' overlay
