{
  description = "Big, girthy package with a lot of dependencies";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs =
    {
      self,
      opam-nix,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (system: {
      legacyPackages =
        let
          inherit (opam-nix.lib.${system}) queryToScope;

          scope = queryToScope { } { tezos = "*"; };
          overlay = self: super: { };
        in
        scope.overrideScope overlay;

      packages.default = self.legacyPackages.${system}.tezos;
    });
}
