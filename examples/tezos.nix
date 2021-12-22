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
    ctypes = super.ctypes.override { ctypes-foreign = null; };
    tezos-rust-libs = super.tezos-rust-libs.overrideAttrs
      (_: { dontPatchShebangsEarly = true; });
  };

in scope.overrideScope' overlay
