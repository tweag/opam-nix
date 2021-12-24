let
  pkgs = import <nixpkgs> { };
  opam-nix = import ../. pkgs;
  repos = {
    default = pkgs.fetchFromGitHub (pkgs.lib.importJSON ./opam-repository.json);
  };
  scope = opam-nix.queryToScope { inherit repos pkgs; } {
    "0install" = null;
    "0install-gtk" = null;
    ocaml = "4.12.1";
  };
in scope
