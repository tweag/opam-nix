pkgs: compiler:
let
  varsFor = pkg: {
    version = pkg.version;
    name = pkg.pname or pkg.name;
    installed = true;
    enable = "enable";
    pinned = false;
    build = null;
    hash = null;
    dev = false;
    build-id = null;
    opamfile = null;
    depends = { };
  };

  otherFor = pkg: { passthru.vars = varsFor pkg; };

  s = builtins.splitVersion compiler;

  compilerVersion = "${builtins.elemAt s 0}_${builtins.elemAt s 1}";

  ocamlPackages =
    pkgs.pkgsBuildHost.ocaml-ng."ocamlPackages_${compilerVersion}";
  ocamlPackages' = pkgs.ocaml-ng."ocamlPackages_${compilerVersion}";

  self = {
    # Passthru the "build" nixpkgs
    nixpkgs = pkgs;

    # These can come from the bootstrap ocamlPackages
    opam-installer = pkgs.pkgsBuildBuild.opam-installer
      // otherFor pkgs.pkgsBuildBuild.opam-installer;
    opam2json = pkgs.pkgsBuildBuild.ocamlPackages.callPackage ./opam2json.nix { };

    # FIXME this should use ocamlPackages (https://github.com/NixOS/nixpkgs/issues/143883)
    # But cross-compilation isn't really a thing for now.
    # We show a warning here instead of failing to allow people to fix things for their specific use-cases
    ocaml = pkgs.lib.warnIf
      (pkgs.stdenv.hostPlatform.system != pkgs.stdenv.buildPlatform.system)
      "Cross-compilation is not supported. See https://github.com/NixOS/nixpkgs/issues/14388"
      ocamlPackages'.ocaml // {
        passthru.vars = {
          native = true;
          preinstalled = true;
          native-dynlink = !pkgs.stdenv.hostPlatform.isStatic;
        } // varsFor ocamlPackages'.ocaml;
      };
  };
in self
