inputs:
pkgs:
let
  opam-nix = inputs.self.lib.${pkgs.system};
  repos = [
    (opam-nix.makeOpamRepo inputs.tezos)
    inputs.opam-repository
  ];

  nixpkgsOverlay = self: super: {
    util-linux = pkgs.util-linux;
  };

  scope = opam-nix.queryToScope { inherit repos; pkgs = pkgs.pkgsStatic.extend nixpkgsOverlay; } {
    tezos = null;
    ocaml = "4.12.1";
  };
  overlay = self: super: {};
in scope.overrideScope' overlay
