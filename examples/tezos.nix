inputs: pkgs:
let
  opam-nix = inputs.self.lib.${pkgs.system};
  repos = [ (opam-nix.makeOpamRepo inputs.tezos) inputs.opam-repository ];

  scope = opam-nix.queryToScope { inherit repos pkgs; } {
    tezos = null;
    ocaml = "4.12.1";
  };
  overlay = self: super:
    {

    };
in scope.overrideScope' overlay
