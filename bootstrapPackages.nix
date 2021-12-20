{ dune_2 ? null, jbuilder ? null, opam-installer ? null, ocaml ? null, findlib ? null, ocamlbuild ? null, odoc ? null }:
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
in rec {
  dune = dune_2 // otherFor dune_2;
  jbuilder = jbuilder // otherFor jbuilder;
  opam-installer = opam-installer // otherFor opam-installer;
  odoc = odoc // otherFor odoc;

  ocamlfind = findlib // otherFor findlib;
  ocaml = ocaml // {
    passthru.vars = {
      native = true;
      preinstalled = false;
    } // varsFor ocaml;
  };
  ocaml-variants = ocaml;
  base = null;
  base-unix = null;
  base-threads = null;
  base-bigarray = null;
  base-ocamlbuild = null;
  base-bytes = null;
  ocaml-system = null;
  ocamlbuild = ocamlbuild;

  conf-which = null;
}
