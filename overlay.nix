self: super:
let
  oa' = f: x: x.overrideAttrs f;
  dontPatchShebangsEarly = oa' (_: { dontPatchShebangsEarly = true; });
  addNativeBuildInputs = nbi:
    oa' (oa: { nativeBuildInputs = oa.nativeBuildInputs ++ nbi; });
  multipleDirectoriesInTarball = oa' (_: { sourceRoot = "."; });

  fixAltErgo = oa' (oa: {
    nativeBuildInputs = oa.nativeBuildInputs ++ [ self.external.which ];
    buildPhase = ''
      runHook preBuild
      "ocaml" "unix.cma" "configure.ml" ${oa.pname} --prefix $out "--libdir" $OCAMLFIND_DESTDIR "--mandir" $out/doc
      "dune" "build" "-p" ${oa.pname} "-j" $NIX_BUILD_CORES
      runHook postBuild
    '';
  });
in {
  cairo2 = super.cairo2.overrideAttrs (oa: {
    NIX_CFLAGS_COMPILE = [ "-I${self.external.freetype.dev}/include/freetype" ];
    buildInputs = oa.buildInputs
      ++ [ self.external.freetype.dev ];
    prePatch = ''
      echo '#define OCAML_CAIRO_HAS_FT 1' > src/cairo_ocaml.h
      cat src/cairo_ocaml.h.p >> src/cairo_ocaml.h
      sed 's,/usr/include/cairo,${self.external.cairo.dev}/include/cairo,' -i config/discover.ml
      sed 's/targets c_flags.sexp c_library_flags.sexp cairo_ocaml.h/targets c_flags.sexp c_library_flags.sexp/' -i src/dune
    '';
  });

  # Use pkg-config without dependency on conf-pkg-config
  lablgtk3 = addNativeBuildInputs [ self.external.pkg-config ] super.lablgtk3;
  lablgtk3-sourceview3 =
    addNativeBuildInputs [ self.external.pkg-config ] super.lablgtk3-sourceview3;

  # Calls opam in configure (WTF)
  alt-ergo-lib = fixAltErgo super.alt-ergo-lib;
  alt-ergo-parsers = fixAltErgo super.alt-ergo-parsers;
  alt-ergo = fixAltErgo super.alt-ergo;

  # Circular dependency
  ctypes-foreign = super.ctypes-foreign.override { ctypes = null; };

  # Verifies checksums of scripts and installs to $OCAMLFIND_DESTDIR
  tezos-rust-libs = super.tezos-rust-libs.overrideAttrs (_: {
    dontPatchShebangsEarly = true;
    postInstall = ''
      mkdir -p $out/include
      mv $OCAMLFIND_DESTDIR/tezos-rust-libs/*.a $out/lib
      mv $OCAMLFIND_DESTDIR/tezos-rust-libs/*.h $out/include
      rm -rf $out/lib/ocaml
    '';
  });

  hacl-star-raw = multipleDirectoriesInTarball super.hacl-star-raw;
  hacl-star = multipleDirectoriesInTarball super.hacl-star;


}
