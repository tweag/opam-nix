inputs:
pkgs:
let
  opam-nix = inputs.self.lib.${pkgs.system};
  repos = [
    (opam-nix.makeOpamRepo inputs.opam2json)
    inputs.opam-repository
  ];
  scope = opam-nix.queryToScope { inherit repos pkgs; } {
    opam2json = null;
    ocaml = "4.12.1";
  };
  overlay = self: super: { };

in scope.overrideScope' overlay
