final: prev:
let
  inherit (prev.nixpkgs) lib;

  inherit (import ./lib.nix lib) applyOverrides;

  ocamlVersion = final.ocaml.passthru.pkgdef.version;

  ocamlVersionList = lib.splitString "." ocamlVersion;

  major = builtins.elemAt ocamlVersionList 0;
  minor = builtins.elemAt ocamlVersionList 1;

  nixpkgsOcamlPackages =
    lib.warnIf (final.nixpkgs.stdenv.hostPlatform.system != final.nixpkgs.stdenv.targetPlatform.system)
      "[opam-nix] Cross-compilation is not supported! This will likely fail. See https://github.com/NixOS/nixpkgs/issues/143883 ."
      final.nixpkgs.ocaml-ng."ocamlPackages_${major}_${minor}" or (throw ''
        [opam-nix] OCaml compiler version ${major}.${minor} couldn't be found in nixpkgs.
        You can try:
        - Providing a different nixpkgs version to opam-nix;
        - Explicitly requiring an OCaml compiler version present in the current nixpkgs version (here are the available versions: ${toString (builtins.attrNames final.nixpkgs.ocaml-ng)});
        - Using an OCaml compiler from opam by explicitly requiring ocaml-base-compiler (possibly instead of ocaml-system).
      '');

  overrides = {
    ocaml-system = oa: {
      # Note that we take ocaml from the same package set as
      nativeBuildInputs = [ nixpkgsOcamlPackages.ocaml ];
    };

    ocaml = oa: {
      opam__ocaml_config__share = "${final.ocaml-config}/share/ocaml-config";
    };

    camlp4 = oa: {
      # Point to the real installation directory
      postInstall = ''
        sed -i 's@directory = "+camlp4"@directory = "../ocaml/camlp4"@' "$out/lib/ocaml/$opam__ocaml__version/site-lib/camlp4/META"
      '';
    };

    # Attempts to install to ocaml root
    num =
      if lib.versionAtLeast prev.num.version "1.4" then
        oa: { opam__ocaml__preinstalled = "true"; }
      else if lib.versionAtLeast prev.num.version "1.0" then
        oa: { patches = final.nixpkgs.ocamlPackages.num.patches; }
      else
        _: { };

    cairo2 = oa: {
      NIX_CFLAGS_COMPILE = [ "-I${final.nixpkgs.freetype.dev}/include/freetype" ];
      buildInputs = oa.buildInputs ++ [ final.nixpkgs.freetype.dev ];
      prePatch =
        oa.prePatch
        + ''
          echo '#define OCAML_CAIRO_HAS_FT 1' > src/cairo_ocaml.h
          cat src/cairo_ocaml.h.p >> src/cairo_ocaml.h
          sed 's,/usr/include/cairo,${final.nixpkgs.cairo.dev}/include/cairo,' -i config/discover.ml
          sed 's/targets c_flags.sexp c_library_flags.sexp cairo_ocaml.h/targets c_flags.sexp c_library_flags.sexp/' -i src/dune
        '';
    };

    ocamlfind = oa: {
      patches =
        lib.optional (lib.versionOlder oa.version "1.9.3") ../../patches/ocamlfind/install_topfind_192.patch
        ++ lib.optional (oa.version == "1.9.3") ../../patches/ocamlfind/install_topfind_193.patch
        ++ lib.optional (
          lib.versionAtLeast oa.version "1.9.4" && lib.versionOlder oa.version "1.9.6"
        ) ../../patches/ocamlfind/install_topfind_194.patch
        ++ lib.optional (
          lib.versionAtLeast oa.version "1.9.6" && lib.versionOlder oa.version "1.9.8"
        ) ../../patches/ocamlfind/install_topfind_196.patch
        ++ lib.optional (lib.versionAtLeast oa.version "1.9.8") ../../patches/ocamlfind/install_topfind_198.patch;
      opam__ocaml__preinstalled = "false"; # Install topfind
      passthru = lib.recursiveUpdate oa.passthru {
        pkgdef.url.section.src = "https://web.archive.org/${oa.passthru.pkgdef.url.section.src}";
      };
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

    feather = oa: {
      nativeBuildInputs = oa.nativeBuildInputs ++ [ final.nixpkgs.procps ];
    };

    camlimages = oa: {
      buildInputs = oa.buildInputs ++ [
        final.nixpkgs.libpng
        final.nixpkgs.libjpeg
      ];
      nativeBuildInputs = oa.nativeBuildInputs ++ [ final.nixpkgs.pkg-config ];
    };
    camlpdf = oa: {
      nativeBuildInputs = oa.nativeBuildInputs ++ [ final.nixpkgs.which ];
    };

    ocaml-solo5 = oa: {
      preBuild = ''
        cp -Lr $opam__ocaml_src__lib/ocaml-src ./ocaml
        chmod -R +rw ./ocaml
        sed -i 's|cp runtime/ocamlrun$(EXE) boot/ocamlrun$(EXE)|rm boot/ocamlrun$(EXE); cp runtime/ocamlrun$(EXE) boot/ocamlrun$(EXE)|g' ocaml/Makefile
        sed -i 's|cp -r `opam var prefix`/lib/ocaml-src ./ocaml|echo "Skipping copying ocaml-src to ./ocaml"|g' Makefile
      '';
    };

    augeas = oa: {
      buildInputs = [
        final.nixpkgs.libxml2
        final.nixpkgs.augeas
      ];
    };

    coq-of-ocaml =
      oa:
      lib.optionalAttrs (lib.versionAtLeast oa.version "2.5.3") {
        sourceRoot = ".";
      };

    coq = oa: {
      setupHook = final.nixpkgs.writeText "setupHook.sh" (
        ''
          addCoqPath () {
            if test -d "$1/lib/coq/${oa.version}/user-contrib"; then
              export COQPATH="''${COQPATH-}''${COQPATH:+:}$1/lib/coq/${oa.version}/user-contrib/"
            fi
          }

          addEnvHooks "$targetOffset" addCoqPath

          # Note that $out refers to the output of a dependent package, not coq itself
          export DESTDIR="$out/lib/coq/${oa.version}"
          export COQLIBINSTALL="$out/lib/coq/${oa.version}/user-contrib"
          export COQPLUGININSTALL="$out/lib/ocaml/${final.ocaml.version}/site-lib"
          export COQUSERCONTRIB="$out/lib/coq/${oa.version}/user-contrib"
        ''
        + lib.optionalString (prev ? coq-stdlib) ''
          export COQLIB="${final.coq-stdlib}/lib/ocaml/${final.ocaml.version}/site-lib/coq"
          export COQCORELIB="${final.coq-core}/lib/ocaml/${final.ocaml.version}/site-lib/coq-core"
        ''
      );
    };

    coq-stdlib = oa: {
      fixupPhase =
        oa.fixupPhase or ""
        + ''
          mkdir -p $out/nix-support
          echo "export COQLIB=\"$out/lib/ocaml/${final.ocaml.version}/site-lib/coq\"" >> $out/nix-support/setup-hook
        '';
    };

    coq-core = oa: {
      fixupPhase =
        oa.fixupPhase or ""
        + ''
          mkdir -p $out/nix-support
          echo "export COQCORELIB=\"$out/lib/ocaml/${final.ocaml.version}/site-lib/coq-core\"" >> $out/nix-support/setup-hook
        '';
    };

    fswatch =
      oa:
      if lib.versionAtLeast oa.version "11-0.1.3" then
        {
          buildPhase = ''
            echo '(-I${prev.nixpkgs.fswatch}/include/libfswatch/c)' > fswatch/src/inc_cflags
            echo '(-lfswatch)' > fswatch/src/inc_libs
            dune build -p $opam__name -j $opam__jobs
          '';
        }
      else
        {
          buildPhase = ''
            sed -i 's@/usr/local/include/libfswatch/c@${prev.nixpkgs.fswatch}/include/libfswatch/c@' fswatch/src/dune
          '';
        };

    ocsigenserver = oa: {
      # Ocsigen installs a FIFO.
      postInstall = ''
        rm -f "$out"/lib/ocaml/*/site-lib/ocsigenserver/var/run/ocsigenserver_command
      '';
    };

    timedesc-tzdb = _: { sourceRoot = "."; };
    timedesc-tzlocal = _: { sourceRoot = "."; };
    timedesc-sexp = _: { sourceRoot = "."; };
    timedesc = _: { sourceRoot = "."; };
    timere = _: { sourceRoot = "."; };

    pyml = oa: if oa.version == "20231101" then { sourceRoot = "."; } else { };

    opam-format = oa: { buildInputs = oa.buildInputs ++ [ final.opam-core ]; };

    opam-repository = oa: { buildInputs = oa.buildInputs ++ [ final.opam-format ]; };

    opam-state = oa: { buildInputs = oa.buildInputs ++ [ final.opam-repository ]; };

    utop = oa: if oa.passthru.pkgdef.version == "2.15.0-1" then { sourceRoot = "."; } else { };
  };
in
lib.optionalAttrs (prev ? ocamlfind-secondary) {
  dune = (prev.dune.override { ocaml = final.nixpkgs.ocaml; }).overrideAttrs (_: {
    postFixup = "rm $out/nix-support -rf";
  });
}
// lib.optionalAttrs (prev ? ctypes) {
  ctypes =
    if prev ? ctypes-foreign then (prev.ctypes.override { ctypes-foreign = null; }) else prev.ctypes;
}
// applyOverrides prev overrides
