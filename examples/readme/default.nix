{ stdenv, lib, pandoc, htmlq, opam-nix, pkgs, readme ? ../../README.md }:
let
  examples = stdenv.mkDerivation {
    name = "readme-check";
    src = ./.;
    nativeBuildInputs = [ pandoc htmlq ];
    phases = [ "unpackPhase" "buildPhase" ];
    buildPhase = ''
      mkdir -p $out
      html="$(pandoc -i ${readme})"
      for id in $(htmlq '.example' -a id <<< $html); do
        dir=$(htmlq ".example#$id" -a dir <<< $html)
        cp -R $dir $out/$id
        htmlq ".example#$id" -t <<< $html >> $out/$id/default.nix
      done
    '';
  };

  checks = lib.mapAttrs' (name: value:
    lib.nameValuePair "readme-${name}" (builtins.scopedImport
    (pkgs // opam-nix)
      "${examples}/${name}")) (builtins.readDir examples);
in checks
