final: prev:
let
  inherit (prev.nixpkgs) lib;

  pkgs = prev.nixpkgs;

  inherit (import ./lib.nix lib) applyOverrides;

  overrides = rec {
    ocurl = oa: {
      buildInputs = oa.buildInputs ++ [ pkgs.curl.dev ];
    };

    conf-which = oa: {
      nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.which ];
    };
  };
in applyOverrides prev overrides
