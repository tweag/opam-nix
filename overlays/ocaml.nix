self: super:
let
  inherit (super.nixpkgs) lib;

  inherit (import ./lib.nix lib) applyOverrides;

  ocamlVersion = self.ocaml.passthru.pkgdef.version;

  ocamlVersionList = lib.splitString "." ocamlVersion;

  major = builtins.elemAt ocamlVersionList 0;
  minor = builtins.elemAt ocamlVersionList 1;

  nixpkgsOcamlPackages = lib.warnIf (self.nixpkgs.stdenv.hostPlatform.system
    != self.nixpkgs.stdenv.targetPlatform.system)
    "Cross-compilation is not supported! This will likely fail."
    self.nixpkgs.ocaml-ng."ocamlPackages_${major}_${minor}";

  overrides = rec {
    ocaml-system = oa: {
      # Note that we take ocaml from the same package set as
      nativeBuildInputs = [ nixpkgsOcamlPackages.ocaml ];
    };

    ocaml = oa: {
      preBuild = ''
        export opam__ocaml_config__share='${self.ocaml-config}/share/ocaml-config'
      '';
    };

    # Attempts to install to ocaml root
    num = if self.nixpkgs.lib.versionAtLeast super.num.version "1.4" then
      oa: {
        preBuild = ''
          export opam__ocaml__preinstalled="true";
        '';
      }
    else
      oa: { patches = self.nixpkgs.ocamlPackages.num.patches; };

    cairo2 = oa: {
      NIX_CFLAGS_COMPILE =
        [ "-I${self.nixpkgs.freetype.dev}/include/freetype" ];
      buildInputs = oa.buildInputs ++ [ self.nixpkgs.freetype.dev ];
      prePatch = ''
        echo '#define OCAML_CAIRO_HAS_FT 1' > src/cairo_ocaml.h
        cat src/cairo_ocaml.h.p >> src/cairo_ocaml.h
        sed 's,/usr/include/cairo,${self.nixpkgs.cairo.dev}/include/cairo,' -i config/discover.ml
        sed 's/targets c_flags.sexp c_library_flags.sexp cairo_ocaml.h/targets c_flags.sexp c_library_flags.sexp/' -i src/dune
      '';
    };

    ocamlfind = oa: {
      patches = oa.patches or [ ] ++ self.nixpkgs.ocamlPackages.findlib.patches;
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
in lib.optionalAttrs (super ? ctypes) {
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
} // applyOverrides super overrides
