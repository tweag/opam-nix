src:
{ stdenv, fetchFromGitHub, opam-installer, ocaml, findlib, yojson, opam-file-format, cmdliner }:
stdenv.mkDerivation {
  pname = "opam2json";
  version = "0.1";

  inherit src;

  buildInputs = [ yojson opam-file-format cmdliner ];
  nativeBuildInputs = [ ocaml findlib opam-installer ];

  preInstall = "export PREFIX=$out";
}
