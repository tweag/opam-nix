{
  inputs = {
    opam-nix.url = "github:tweag/opam-nix";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, flake-utils, opam-nix }@inputs:
    let package = throw "Put the package name here!";
    in flake-utils.lib.eachSystem [ "x86_64-linux" ] (system: {
      legacyPackages = let
        opam-nix = inputs.opam-nix.lib.${system};
        scope = opam-nix.queryToScope {
          repos = [
            (opam-nix.makeOpamRepo self)
            inputs.opam-nix.inputs.opam-repository
          ];
        } {
          # Get the latest possible version of your package
          ${package} = null;
          # Comment out the next two lines if you want to use the compiler provided by nixpkgs
          ocaml-base-compiler =
            "4.12.0"; # Change the version here if you want a different ocaml version
        };
        overlay = self: super:
          {
            # Your overrides go here
          };
      in scope.overrideScope' overlay;

      defaultPackage =
        self.legacyPackages.${system}.${package};
    });
}
