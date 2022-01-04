final: prev:
let
  inherit (prev.nixpkgs) lib;

  inherit (import ./lib.nix lib) applyOverrides;

  overrides = rec {
    ocurl = oa: {
      buildInputs = oa.buildInputs ++ [ prev.nixpkgs.curl.dev ];
    };
  };
in applyOverrides prev overrides
