let
  pkgs = import <nixpkgs> { };
  opam-nix = import ../. pkgs;
  repos = {
    default = pkgs.fetchFromGitHub (pkgs.lib.importJSON ./opam-repository.json);

    tezos = opam-nix.makeOpamRepo (pkgs.fetchgit {
      url = "https://gitlab.com/tezos/tezos.git";
      rev = "7a8c3312f7f02d8c143164352ce8564f856ddcd5"; # v12.0-rc1
      sha256 = "sha256-1/u8tWP0yuB0omCq54Lfp+Rkr/IUUV21RjUt7hGdU+8=";
    });
  };
  scope = opam-nix.queryToScope { inherit repos pkgs; } {
    tezos = null;
    ocaml = "4.12.1";
  };
  overlay = self: super: {};
in scope.overrideScope' overlay
