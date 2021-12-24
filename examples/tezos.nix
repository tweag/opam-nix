let
  pkgs = import <nixpkgs> { };
  opam-nix = import ../. pkgs;
  repos.default =
    pkgs.fetchFromGitHub (pkgs.lib.importJSON ./opam-repository.json);
  scope = opam-nix.queryToScope { inherit repos pkgs; } {
    tezos = null;
    ocaml = "4.12.1";
  };
  overlay = self: super: {
  };

in scope.overrideScope' overlay
