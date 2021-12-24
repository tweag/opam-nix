inputs:
pkgs:
let
  opam-nix = inputs.self.lib.${pkgs.system};

  repos = [
    inputs.opam-repository
  ];
  scope = opam-nix.queryToScope { inherit repos pkgs; } {
    "0install" = null;
    "0install-gtk" = null;
    ocaml = "4.12.1";
  };
in scope
