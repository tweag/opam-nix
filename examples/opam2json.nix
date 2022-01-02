# Example of using a custom opam repository
inputs: pkgs:
let
  opam-nix = inputs.self.lib.${pkgs.system};
  scope = opam-nix.buildOpamProject inputs.opam2json {};
in scope
