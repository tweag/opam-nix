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

    conf-m4 = oa: { nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.m4 ]; };

    conf-perl = oa: {
      nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.perl ];
    };

    conf-libssl = oa: {
      # TODO add openssl to buildInputs?
      nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.pkg-config ];
      buildPhase = ''
        pkg-config --print-errors --exists openssl
      '';
      installPhase = "mkdir $out";
    };

    dune =
      oa: with pkgs; {
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

    digestif = oa: { dontPatchShebangsEarly = true; };

    conf-cairo = oa: { buildPhase = "pkg-config --libs cairo"; };

    class_group_vdf = oa: {
      # Similar to https://github.com/NixOS/nixpkgs/issues/127608
      hardeningDisable = [ "stackprotector" ];
    };

    conf-libpcre = oa: {
      nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.pkg-config ];
    };
    conf-libpcre2-8 = oa: {
      nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.pkg-config ];
    };
    conf-libffi = oa: {
      nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.pkg-config ];
    };

    caqti = oa: {
      nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.darwin.sigtool ];
    };
  };
in
applyOverrides prev overrides
// {
  re2 = (prev.re2.override { "conf-g++" = null; }).overrideAttrs (oa: {
    prePatch =
      oa.prePatch
      + ''
        substituteInPlace src/re2_c/dune --replace 'CXX=g++' 'CXX=c++'
        substituteInPlace src/dune --replace '(cxx_flags (:standard \ -pedantic) (-I re2_c/libre2))' '(cxx_flags (-undefined dynamic_lookup :standard \ -pedantic) (-I re2_c/libre2) (-x c++))'
      '';
  });
}
