{ dune_2 ? null, jbuilder ? null, opam-installer ? null, ocaml ? null, findlib ? null, ocamlbuild ? null, odoc ? null, ... }:
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
  };

  otherFor = pkg: {
    passthru.vars = varsFor pkg;
  };
in {
  dune = dune_2 // otherFor dune_2;
  jbuilder = jbuilder // otherFor jbuilder;
  opam-installer = opam-installer // otherFor opam-installer;
  odoc = odoc // otherFor odoc;

  ocamlfind = findlib // otherFor findlib;
  ocaml = ocaml // {
    passthru.vars = {
      native = "true";
      preinstalled = "false";
      native-dynlink = "true";
    } // varsFor ocaml;
  };
  ocamlbuild = ocamlbuild;
}
