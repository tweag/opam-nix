{
  inputs = {
    opam-nix.url = "github:tweag/opam-nix";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, flake-utils, opam-nix }@inputs:
    let package = throw "Put the package name here!";
    in flake-utils.lib.eachSystem [ "x86_64-linux" ] (system: {
      legacyPackages = let
        inherit (opam-nix.lib.${system}) buildOpamProject;
        scope = buildOpamProject { } ./. { };
        overlay = self: super:
          {
            # Your overrides go here
          };
      in scope.overrideScope' overlay;

      defaultPackage = self.legacyPackages.${system}.${package};
    });
}
