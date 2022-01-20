final: prev:
let
  inherit (prev.nixpkgs) lib;

  pkgs = prev.nixpkgs;

  inherit (import ./lib.nix lib) applyOverrides;

  overrides = rec {
    ocurl = oa: { buildInputs = oa.buildInputs ++ [ pkgs.curl.dev ]; };

    conf-which = oa: {
      nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.which ];
    };

    conf-libssl = oa: {
      # TODO add openssl to buildInputs?
      nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.pkg-config ];
      buildPhase = ''
        pkg-config --print-errors --exists openssl
      '';
      installPhase = "true";
    };

    zarith = oa: {
      buildPhase = ''
        ./configure
        make
      '';
    };
  };
in applyOverrides prev overrides
