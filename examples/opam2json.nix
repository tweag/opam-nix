# Example of using a custom opam repository
inputs: pkgs:
let
  opam-nix = inputs.self.lib.${pkgs.system};
  repos = [ (opam-nix.makeOpamRepo inputs.opam2json) inputs.opam-repository ];
  scope = opam-nix.queryToScope { inherit repos pkgs; } {
    opam2json = null;
  };
  overlay = self: super: { };

in scope.overrideScope' overlay
