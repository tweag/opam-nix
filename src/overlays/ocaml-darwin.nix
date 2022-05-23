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

    conf-m4 = oa: {
      nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.m4 ];
    };

    conf-perl = oa: {
      nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.perl ];
    };

    conf-libssl = oa: {
      # TODO add openssl to buildInputs?
      nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.pkg-config ];
      buildPhase = ''
        pkg-config --print-errors --exists openssl
      '';
      installPhase = "true";
    };

    dune = oa:
      with pkgs; {
        buildInputs = oa.buildInputs ++ [
          darwin.apple_sdk.frameworks.Foundation
          darwin.apple_sdk.frameworks.CoreServices
        ];
      };

    zarith = oa: {
      buildPhase = ''
        ./configure
        make
      '';
    };

    digestif = oa: {
      dontPatchShebangsEarly = true;
    };

    re2 = oa: {
      prePatch = oa.prePatch + ''
        substituteInPlace src/re2_c/dune --replace 'CXX=g++' 'CXX=c++'
        substituteInPlace src/dune --replace '(cxx_flags (:standard \ -pedantic) (-I re2_c/libre2))' '(cxx_flags (:standard \ -pedantic) (-I re2_c/libre2) (-x c++))'
      '';
    };

  };
in applyOverrides prev overrides
