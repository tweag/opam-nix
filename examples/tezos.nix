# A big, girthy application with a big dependency tree
inputs: pkgs:
let
  opam-nix = inputs.self.lib.${pkgs.system};

  scope = opam-nix.queryToScope { inherit pkgs; } {
    tezos = null;
    ocaml-base-compiler = null;
  };
  overlay = self: super: { };
in scope.overrideScope' overlay
