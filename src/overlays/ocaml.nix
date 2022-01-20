final: prev:
let
  inherit (prev.nixpkgs) lib;

  inherit (import ./lib.nix lib) applyOverrides;

  ocamlVersion = final.ocaml.passthru.pkgdef.version;

  ocamlVersionList = lib.splitString "." ocamlVersion;

  major = builtins.elemAt ocamlVersionList 0;
  minor = builtins.elemAt ocamlVersionList 1;

  nixpkgsOcamlPackages = lib.warnIf (final.nixpkgs.stdenv.hostPlatform.system
    != final.nixpkgs.stdenv.targetPlatform.system)
    "Cross-compilation is not supported! This will likely fail."
    final.nixpkgs.ocaml-ng."ocamlPackages_${major}_${minor}";

  overrides = rec {
    ocaml-system = oa: {
      # Note that we take ocaml from the same package set as
      nativeBuildInputs = [ nixpkgsOcamlPackages.ocaml ];
    };

    ocaml = oa: {
      opam__ocaml_config__share = "${final.ocaml-config}/share/ocaml-config";
    };

    # Attempts to install to ocaml root
    num = if final.nixpkgs.lib.versionAtLeast prev.num.version "1.4" then
      oa: { opam__ocaml__preinstalled = "true"; }
    else if final.nixpkgs.lib.versionAtLeast prev.num.version "1.0" then
      oa: { patches = final.nixpkgs.ocamlPackages.num.patches; }
    else
      _: { };

    cairo2 = oa: {
      NIX_CFLAGS_COMPILE =
        [ "-I${final.nixpkgs.freetype.dev}/include/freetype" ];
      buildInputs = oa.buildInputs ++ [ final.nixpkgs.freetype.dev ];
      prePatch = ''
        echo '#define OCAML_CAIRO_HAS_FT 1' > src/cairo_ocaml.h
        cat src/cairo_ocaml.h.p >> src/cairo_ocaml.h
        sed 's,/usr/include/cairo,${final.nixpkgs.cairo.dev}/include/cairo,' -i config/discover.ml
        sed 's/targets c_flags.sexp c_library_flags.sexp cairo_ocaml.h/targets c_flags.sexp c_library_flags.sexp/' -i src/dune
      '';
    };

    ocamlfind = oa: {
      patches = oa.patches or [ ]
        ++ final.nixpkgs.ocamlPackages.findlib.patches;
      opam__ocaml__preinstalled = "false"; # Install topfind
    };

    # Verifies checksums of scripts and installs to $OCAMLFIND_DESTDIR
    tezos-rust-libs = _: {
      dontPatchShebangsEarly = true;
      postInstall = ''
        mkdir -p $out/include
        mv $OCAMLFIND_DESTDIR/tezos-rust-libs/*.a $out/lib
        mv $OCAMLFIND_DESTDIR/tezos-rust-libs/*.h $out/include
        rm -rf $out/lib/ocaml
      '';
    };

    hacl-star-raw = _: { sourceRoot = "."; };
    hacl-star = _: { sourceRoot = "."; };
  };
in lib.optionalAttrs (prev ? ocamlfind-secondary) {
  dune = (prev.dune.override { ocaml = final.nixpkgs.ocaml; }).overrideAttrs
    (_: { postFixup = "rm $out/nix-support -rf"; });
} // lib.optionalAttrs (prev ? ctypes) rec {
  # Weird virtual package setup, we have to manually "untie" the fix knot
  ctypes = if prev ? ctypes-foreign then
    (prev.ctypes.override { ctypes-foreign = null; }).overrideAttrs (oa: {
      pname = "ctypes";
      opam__ctypes_foreign__installed = "true";
      nativeBuildInputs = oa.nativeBuildInputs
        ++ prev.ctypes-foreign.nativeBuildInputs;
      buildInputs = oa.buildInputs ++ [ final.nixpkgs.libffi ];
    })
  else
    prev.ctypes;
}
// lib.optionalAttrs (prev ? ctypes-foreign) { ctypes-foreign = final.ctypes; }
// applyOverrides prev overrides
