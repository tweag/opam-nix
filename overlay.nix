self: super: {
  cairo2 = super.cairo2.overrideAttrs (oa: {
    NIX_CFLAGS_COMPILE = [ "-I${self.native.freetype.dev}/include/freetype" ];
    propagatedBuildInputs = oa.propagatedBuildInputs ++ [ self.native.freetype.dev ];
    prePatch = ''
      echo '#define OCAML_CAIRO_HAS_FT 1' > src/cairo_ocaml.h
      cat src/cairo_ocaml.h.p >> src/cairo_ocaml.h
      sed 's,/usr/include/cairo,${self.native.cairo.dev}/include/cairo,' -i config/discover.ml
      sed 's/targets c_flags.sexp c_library_flags.sexp cairo_ocaml.h/targets c_flags.sexp c_library_flags.sexp/' -i src/dune
    '';
  });
  lablgtk3 = super.lablgtk3.overrideAttrs (oa: {
    nativeBuildInputs = oa.nativeBuildInputs ++ [ self.native.pkg-config ];
  });

  lablgtk3-sourceview3 = super.lablgtk3-sourceview3.overrideAttrs (oa: {
    nativeBuildInputs = oa.nativeBuildInputs ++ [ self.native.pkg-config ];
  });

  ctypes = super.ctypes.override { ctypes-foreign = null; };
  tezos-rust-libs =
    super.tezos-rust-libs.overrideAttrs (_: { dontPatchShebangsEarly = true; });

  # Calls opam in configure (WTF)
  alt-ergo-lib = super.alt-ergo-lib.overrideAttrs (oa: {
    nativeBuildInputs = oa.nativeBuildInputs ++ [ self.native.which ];
    buildPhase = ''
      runHook preBuild
      "ocaml" "unix.cma" "configure.ml" ${oa.pname} --prefix $out "--libdir" $OCAMLFIND_DESTDIR "--mandir" $out/doc
      "dune" "build" "-p" ${oa.pname} "-j" $NIX_BUILD_CORES
      runHook postBuild
    '';
  });

  alt-ergo-parsers = super.alt-ergo-lib.overrideAttrs (oa: {
    nativeBuildInputs = oa.nativeBuildInputs ++ [ self.native.which ];
    buildPhase = ''
      runHook preBuild
      "ocaml" "unix.cma" "configure.ml" ${oa.pname} --prefix $out "--libdir" $OCAMLFIND_DESTDIR "--mandir" $out/doc
      "dune" "build" "-p" ${oa.pname} "-j" $NIX_BUILD_CORES
      runHook postBuild
    '';
  });

  alt-ergo = super.alt-ergo-lib.overrideAttrs (oa: {
    nativeBuildInputs = oa.nativeBuildInputs ++ [ self.native.which ];
    buildPhase = ''
      runHook preBuild
      "ocaml" "unix.cma" "configure.ml" ${oa.pname} --prefix $out "--libdir" $OCAMLFIND_DESTDIR "--mandir" $out/doc
      "dune" "build" "-p" ${oa.pname} "-j" $NIX_BUILD_CORES
      runHook postBuild
    '';
  });

}
