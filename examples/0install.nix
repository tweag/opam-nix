# Build using the compiler from opam
inputs:
pkgs:
let
  opam-nix = inputs.self.lib.${pkgs.system};
  scope = opam-nix.queryToScope { } {
    "0install" = null;
    # The following line forces opam to choose the compiler from opam instead of the nixpkgs one
    ocaml-base-compiler = null;
  };
in scope
