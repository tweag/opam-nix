self: super:
let

  fake-cxx = self.nixpkgs.writeShellScriptBin "g++" ''$CXX "$@"'';
  fake-cc = self.nixpkgs.writeShellScriptBin "cc" ''$CC "$@"'';

in {
  ocaml-base-compiler = super.ocaml-base-compiler.overrideAttrs (oa: {
    buildPhase = ''
      ./configure \
        --prefix=$out \
        --disable-shared \
        --enable-static \
        --host=${self.nixpkgs.stdenv.hostPlatform.config} \
        --target=${self.nixpkgs.stdenv.targetPlatform.config} \
        -C
      make -j$NIX_BUILD_CORES
    '';
    hardeningDisable = [ "pie" ] ++ oa.hardeningDisable or [];
  });

  "conf-g++" = super."conf-g++".overrideAttrs
    (oa: { nativeBuildInputs = oa.nativeBuildInputs ++ [ fake-cxx ]; });

  sodium = super.sodium.overrideAttrs (oa: {
    buildInputs = oa.buildInputs ++ [ self.nixpkgs.sodium-static ];
    nativeBuildInputs = oa.nativeBuildInputs ++ [ fake-cc ];
  });

  conf-gmp = super.conf-gmp.overrideAttrs
    (oa: { nativeBuildInputs = oa.nativeBuildInputs ++ [ fake-cc ]; });

  base58 = super.base58.overrideAttrs (oa: {
    buildPhase = ''
      make lib.byte
      ocamlbuild -I src -I tests base58.cmxa
    '';
  });

  zarith = super.zarith.overrideAttrs (oa: {
    preBuild = ''
      sed "s/ar='ar'/ar='$AR'/" -i configure
    '';
  });

  digestif = super.digestif.overrideAttrs (oa: {
    buildPhase = ''
      dune build -p digestif -j $NIX_BUILD_CORES
    '';
  });

  cmdliner = super.cmdliner.overrideAttrs (oa: {
    buildPhase = ''
      make build-byte build-native
    '';
    installPhase = ''
      make PREFIX=$out LIBDIR=$OCAMLFIND_DESTDIR/cmdliner install-common install-native
    '';
  });

  ocaml-extlib = super.ocaml-extlib.overrideAttrs (oa: {
    buildPhase = ''
      make -C src all opt
    '';
  });

  ocamlgraph = super.ocamlgraph.overrideAttrs (oa: {
    buildPhase = ''
      ./configure
      sed 's/graph.cmxs//' -i Makefile
      make NATIVE_DYNLINK=false
    '';
  });

  opam-file-format = super.opam-file-format.overrideAttrs
    (_: { buildPhase = "make opam-file-format.cma opam-file-format.cmxa"; });
}
