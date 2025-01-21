final: prev:
let

  inherit (import ./lib.nix prev.nixpkgs.lib) applyOverrides;

  fake-cxx = final.nixpkgs.writeShellScriptBin "g++" ''$CXX "$@"'';
  fake-cc = final.nixpkgs.writeShellScriptBin "cc" ''$CC "$@"'';
  overrides = {
    ocaml-base-compiler = oa: {
      buildPhase = ''
        ./configure \
          --prefix=$out \
          --disable-shared \
          --enable-static \
          --host=${final.nixpkgs.stdenv.hostPlatform.config} \
          --target=${final.nixpkgs.stdenv.targetPlatform.config} \
          -C
        make -j$NIX_BUILD_CORES
      '';
      hardeningDisable = [ "pie" ] ++ oa.hardeningDisable or [ ];
    };

    "conf-g++" = oa: {
      nativeBuildInputs = oa.nativeBuildInputs ++ [ fake-cxx ];
    };

    sodium = oa: {
      buildInputs = oa.buildInputs ++ [ final.nixpkgs.sodium-static ];
      nativeBuildInputs = oa.nativeBuildInputs ++ [ fake-cc ];
    };

    conf-gmp = oa: { nativeBuildInputs = oa.nativeBuildInputs ++ [ fake-cc ]; };

    base58 = oa: {
      buildPhase = ''
        make lib.byte
        ocamlbuild -I src -I tests base58.cmxa
      '';
    };

    zarith = oa: {
      preBuild = ''
        sed "s/ar='ar'/ar='$AR'/" -i configure
      '';
    };

    digestif = oa: {
      buildPhase = ''
        dune build -p digestif -j $NIX_BUILD_CORES
      '';
    };

    cmdliner = oa: {
      buildPhase = ''
        make build-byte build-native
      '';
      installPhase = ''
        make PREFIX=$out LIBDIR=$OCAMLFIND_DESTDIR/cmdliner install-common install-native
      '';
    };

    ocaml-extlib = oa: {
      buildPhase = ''
        make -C src all opt
      '';
    };

    ocamlgraph = oa: {
      buildPhase = ''
        ./configure
        sed 's/graph.cmxs//' -i Makefile
        make NATIVE_DYNLINK=false
      '';
    };

    opam-file-format = _: {
      buildPhase = "make opam-file-format.cma opam-file-format.cmxa";
    };
  };
in
applyOverrides prev overrides
