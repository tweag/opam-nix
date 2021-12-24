let
  pkgs = import <nixpkgs> { };
  opam-nix = import ../. pkgs;
  repos.default =
    pkgs.fetchFromGitHub (pkgs.lib.importJSON ./opam-repository.json);
  scope = opam-nix.queryToScope { inherit repos pkgs; } {
    tezos-client = null;
    ocaml = "4.12.1";
  };
  overlay = self: super: {
    hacl-star-raw = super.hacl-star-raw.overrideAttrs (_: {
      sourceRoot = ".";
    });
  };

in scope.overrideScope' overlay
