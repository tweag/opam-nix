{
  description = "Test for extra-files (files/ directory) support";
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
        inherit (opam-nix.lib.${system}) makeOpamRepoRec opamRepository queryToScope;
        repo = makeOpamRepoRec ./repo;
        scope =
          queryToScope
            {
              repos = [
                repo
                opamRepository
              ];
            }
            {
              ocaml-base-compiler = "*";
              with-extra-files = "*";
            };
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = scope.with-extra-files;

        # The package installs nothing by itself: `greeting.txt` reaches the
        # output only through `files/with-extra-files.install`. Note that a
        # missing .install file is not an error, it just installs nothing, so
        # this has to be checked on the output rather than on the build.
        checks.extra-files-installed = pkgs.runCommand "check-extra-files-installed" { } ''
          if test -f "${scope.with-extra-files}/lib/ocaml/${scope.ocaml.version}/site-lib/with-extra-files/greeting.txt"; then
            echo "SUCCESS: greeting.txt was installed by the bundled .install file"
            touch $out
          else
            echo "FAILURE: greeting.txt was not installed"
            exit 1
          fi
        '';

        # `files/not-a-package.opam` is an extra-file, not a package definition.
        checks.extra-files-not-a-package =
          assert pkgs.lib.assertMsg (
            !(repo.passthru.pkgdefs ? not-a-package)
          ) "an opam file in files/ was taken for a package definition";
          pkgs.runCommand "check-extra-files-not-a-package" { } "touch $out";
      }
    );
}
