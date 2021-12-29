# Regular build using the compiler from opam
inputs:
pkgs:
let
  opam-nix = inputs.self.lib.${pkgs.system};

  repos = [
    inputs.opam-repository
  ];
  scope = opam-nix.queryToScope { inherit repos pkgs; } {
    "0install" = null;
    ocaml-base-compiler = null;
  };
in scope
