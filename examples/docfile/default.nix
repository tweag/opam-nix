{ stdenv, lib, pandoc, htmlq, opam-nix, pkgs, docfile ? ../../DOCUMENTATION.md }:
let
  examples = stdenv.mkDerivation {
    name = "docfile-check";
    src = ./.;
    nativeBuildInputs = [ pandoc htmlq ];
    phases = [ "unpackPhase" "buildPhase" ];
    buildPhase = ''
      mkdir -p $out
      html="$(pandoc -i ${docfile})"
      for id in $(htmlq '.example' -a id <<< $html); do
        dir=$(htmlq ".example#$id" -a dir <<< $html)
        cp -R $dir $out/$id
        htmlq ".example#$id" -t <<< $html >> $out/$id/default.nix
      done
    '';
  };
in {
  checks = lib.mapAttrs' (name: value:
    lib.nameValuePair "docfile-${name}"
    (builtins.scopedImport (pkgs // opam-nix) "${examples}/${name}"))
    (builtins.readDir examples);
}
