{ stdenv, fetchzip, bison, flex_2_5_35 }:
stdenv.mkDerivation {
  pname = "mccs";
  version = "1.1";

  nativeBuildInputs = [ bison flex_2_5_35 ];

  installPhase = ''
    mkdir -p "$out/bin"
    cp mccs "$out/bin"
  '';

  src = fetchzip {
    url = "https://www.i3s.unice.fr/~cpjm/misc/mccs-1.1-srcs.tgz";
    sha256 = "sha256-PaNPSjdScDP42oflHqkiwVYn6RSEuHXANQ/5oePx4/A=";
  };
}
