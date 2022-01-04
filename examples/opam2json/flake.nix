{
  description = "Build an opam project not in the repo, using sane defaults";
  inputs.opam-nix.url = "github:tweag/opam-nix";
  outputs = { self, opam-nix, opam2json }: {
    legacyPackages.x86_64-linux = let
      inherit (opam-nix.lib.x86_64-linux) buildOpamProject;
      scope = buildOpamProject { } opam2json { };
    in scope;
    defaultPackage.x86_64-linux = self.legacyPackages.x86_64-linux.opam2json;
  };
}
