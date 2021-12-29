self: super:
let
  oa' = f: x: x.overrideAttrs f;
  dontPatchShebangsEarly = oa' (_: { dontPatchShebangsEarly = true; });
  addNativeBuildInputs = nbi:
    oa' (oa: { nativeBuildInputs = oa.nativeBuildInputs ++ nbi; });
  multipleDirectoriesInTarball = oa' (_: { sourceRoot = "."; });

in rec {
  ocaml = super.ocaml.overrideAttrs (oa: {
    preBuild = ''
      export opam__ocaml_config__share='${self.ocaml-config}/share/ocaml-config'
    '';
  });

  # Attempts to install to ocaml root
  num = if self.nixpkgs.lib.versionAtLeast super.num.version "1.4" then
    super.num.overrideAttrs (oa: {
      preBuild = ''
        export opam__ocaml__preinstalled="true";
      '';
    })
  else
    super.num.overrideAttrs (oa: {
      patches = self.nixpkgs.ocamlPackages.num.patches;
    });

  cairo2 = super.cairo2.overrideAttrs (oa: {
    NIX_CFLAGS_COMPILE = [ "-I${self.nixpkgs.freetype.dev}/include/freetype" ];
    buildInputs = oa.buildInputs ++ [ self.nixpkgs.freetype.dev ];
    prePatch = ''
      echo '#define OCAML_CAIRO_HAS_FT 1' > src/cairo_ocaml.h
      cat src/cairo_ocaml.h.p >> src/cairo_ocaml.h
      sed 's,/usr/include/cairo,${self.nixpkgs.cairo.dev}/include/cairo,' -i config/discover.ml
      sed 's/targets c_flags.sexp c_library_flags.sexp cairo_ocaml.h/targets c_flags.sexp c_library_flags.sexp/' -i src/dune
    '';
  });

  # Weird virtual package setup, we have to manually "untie" the fix knot
  ctypes = if super ? ctypes-foreign then
    (super.ctypes.override { ctypes-foreign = null; }).overrideAttrs (oa: {
      pname = "ctypes";
      opam__ctypes_foreign__installed = "true";
      nativeBuildInputs = oa.nativeBuildInputs
        ++ super.ctypes-foreign.nativeBuildInputs;
    })
  else
    super.ctypes;

  ctypes-foreign = self.ctypes;

  ocamlfind = super.ocamlfind.overrideAttrs (oa: {
    patches = oa.patches or [ ] ++ self.nixpkgs.ocamlPackages.findlib.patches;
    opam__ocaml__preinstalled = "false"; # Install topfind
  });

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
