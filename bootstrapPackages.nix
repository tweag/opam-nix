pkgs:
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

  self = with ocamlPackages; {
    dune = dune_2 // otherFor dune_2;
    opam-installer = pkgs.opam-installer // otherFor pkgs.opam-installer;
    odoc = odoc // otherFor odoc;

    ocamlfind = findlib // otherFor findlib;
    ocaml = ocaml // {
      passthru.vars = {
        native = true;
        preinstalled = false;
        native-dynlink = true;
      } // varsFor ocaml;
    };
    ocamlbuild = ocamlbuild // otherFor ocamlbuild;

    native = pkgs;

    num = num // otherFor num;
    ocaml-base-compiler = self.ocaml;
  };
in self
