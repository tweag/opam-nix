{
  description = "Test for toplevel files installation (down package)";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.opam-nix.url = "github:tweag/opam-nix";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs =
    {
      self,
      nixpkgs,
      opam-nix,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        scope = opam-nix.lib.${system}.queryToScope { } {
          ocaml-base-compiler = "*";
          down = "*";
        };
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = scope.down;

        checks.toplevel-installed = pkgs.runCommand "check-toplevel-installed" { } ''
          if test -f "${scope.down}/lib/ocaml/${scope.ocaml.version}/site-lib/toplevel/down.top"; then
            echo "SUCCESS: down.top found in toplevel directory"
            touch $out
          else
            echo "FAILURE: down.top not found"
            exit 1
          fi
        '';
      }
    );
}
