{
  inputs = {
    opam-nix.url = "github:tweag/opam-nix";
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.follows = "opam-nix/nixpkgs";
  };
  outputs = { self, flake-utils, opam-nix, nixpkgs }@inputs:
    let package = throw "Put the package name here!";
    in flake-utils.lib.eachDefaultSystem (system: {
      legacyPackages = let
        pkgs = nixpkgs.legacyPackages.${system};
        on = opam-nix.lib.${system};
        scope = on.buildOpamProject { } package ./. { };
        overlay = self: super:
          {
            # Your overrides go here
          };
      in scope.overrideScope' overlay;

      defaultPackage = self.legacyPackages.${system}.${package};
    });
}
