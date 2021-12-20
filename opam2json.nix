{ stdenv, fetchFromGitHub, opam-installer, ocaml, findlib, yojson, opam-file-format, cmdliner }:
stdenv.mkDerivation {
  pname = "opam2json";
  version = "0.1";

  src = fetchFromGitHub {
    owner = "tweag";
    repo = "opam2json";
    rev = "db0cecf937f5f57ec1149120e56652816d8a1b51";
    sha256 = "r55h5B9mRQ9JM/82XZNrkO4/0HyiP2Wt1S7IZtcupCc=";
    fetchSubmodules = true;
  };

  buildInputs = [ yojson opam-file-format cmdliner ];
  nativeBuildInputs = [ ocaml findlib opam-installer ];

  preInstall = "export PREFIX=$out";
}
