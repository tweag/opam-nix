pkgs:
buildPackages:
compiler:
let
  varsFor = pkg: {
    version = pkg.version;
    name = pkg.pname or pkg.name;
    installed = true;
    preinstalled = true;
    enable = "enable";
    pinned = false;
    build = null;
    hash = null;
    dev = false;
    build-id = null;
    opamfile = null;
    depends = { };

    bin = "${pkg}/bin";
    sbin = "${pkg}/bin";
    lib = "${pkg}/lib";
    man = "${pkg}/share/man";
    doc = "${pkg}/share/doc";
    share = "${pkg}/share";
    etc = "${pkg}/etc";

    __toString = self: self.version;
  };

  otherFor = pkg: { passthru.vars = varsFor pkg; };

  s = builtins.splitVersion compiler;

  compilerVersion = "${builtins.elemAt s 0}_${builtins.elemAt s 1}";

  ocamlPackages = pkgs.ocaml-ng."ocamlPackages_${compilerVersion}";

  self = {
    # Passthru the "build" nixpkgs
    nixpkgs = pkgs;

    buildPackages = buildPackages;

    # These can come from the bootstrap ocamlPackages
    opam-installer = buildPackages.opam-installer // otherFor buildPackages.opam-installer;

    # Take ocaml and friends from correct "build" ocamlPackages
    ocaml = ocamlPackages.ocaml // {
      passthru.vars = {
        native = true;
        preinstalled = false;
        native-dynlink = ! pkgs.stdenv.hostPlatform.isStatic;
      } // varsFor ocamlPackages.ocaml;
    };
    num = ocamlPackages.num // otherFor ocamlPackages.num;
    ocaml-base-compiler = self.ocaml;
    ocamlfind = ocamlPackages.findlib // otherFor ocamlPackages.findlib;
  };
in self
