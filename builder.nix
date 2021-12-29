lib:

let
  inherit (builtins)
    elem isString isList isBool isInt concatMap toJSON listToAttrs
    compareVersions head all elemAt length match filter split concatStringsSep
    concatLists attrValues foldl' trace toFile;
  inherit (lib)
    converge filterAttrsRecursive nameValuePair splitString optional hasSuffix
    optionalString concatMapStringsSep foldl mergeAttrsConcatenateValues
    mapAttrs hasAttrByPath getAttrFromPath tail optionalAttrs optionals
    recursiveUpdate escapeShellArg;

  inherit (import ./opam-evaluator.nix lib)
    collectAllDeps val functionArgsFor relevantDepends pkgVarsFor setVars
    evalSection normalize normalize' evalFilter getHashes setEnv;

  alwaysNative = import ./always-native.nix;

  globalVariables = import ./global-variables.nix;

  fallbackPackageVars = name: {
    inherit name;
    installed = "false";
    enable = "disable";
    version = "";
  };
in { name, version, ... }@pkgdef: rec {

  __functionArgs = {
    extraDeps = true;
    extraVars = true;
    nixpkgs = false;
    buildPackages = false;

    opam-installer = true;
    opam2json = true;
    ocaml = true;
  } // functionArgsFor pkgdef;

  __functor = self: deps:
    let
      inherit (deps) opam2json;
      inherit (deps.nixpkgs) stdenv;
      inherit (deps.nixpkgs.pkgsBuildBuild)
        envsubst writeText writeShellScriptBin writeShellScript unzip
        emptyDirectory opam-installer jq;

      # We have to resolve which packages we want at eval-time, except for with-test.
      # This is because mkDerivation is smart with checkInputs: it will only include them in the derivation if doCheck = true.
      # We can't do the same for with-doc (or in general), since it's not possible for us to know what the value of
      # e.g. doDoc is at the eval-time here. ...maybe if mkDerivation took a function and fixed it...

      # I have considered using installCheckPhase and installCheckInputs for docs,
      # but this feels like a massive hack for not much benefit, so we just never build docs.
      versionResolutionVars = globalVariables // pkgdef // {
        with-test = false;
        with-doc = false;
        build = true;
        post = false;
        version = pkgdef.version;
        _ = pkgdef;
        ${name} = pkgdef;
      } // (mapAttrs (name: dep: dep.version or null) deps)
        // deps.extraVars or { };

      dependsNames =
        relevantDepends versionResolutionVars pkgdef.depends or [ ];
      depoptsNames =
        relevantDepends versionResolutionVars pkgdef.depopts or [ ];

      ocamlInputs = map
        (x: deps.${val x} or (lib.warn "${name}: missing dep: ${val x}" null))
        dependsNames ++ map (x:
          deps.${val x} or (trace
            "${name}: missing optional dependency ${val x}" null)) depoptsNames;

      packageDepends = removeAttrs deps [ "extraDeps" "extraVars" "stdenv" ];

      stubOutputs = rec { build = "$NIX_BUILD_TOP/$sourceRoot"; };

      # FIXME: Read extra env variables from `.install` file (this SUCKS)
      vars = {
        inherit name version;
        installed = true;
        enable = "enable";
        pinned = false;
        build = null;
        hash = null;
        dev = false;
        build-id = null;
        opamfile = null;

        prefix = "$out";
        bin = "$out/bin";
        sbin = "$out/bin";
        lib = "$out/lib/ocaml/\${opam__ocaml__version}/site-lib";
        man = "$out/share/man";
        doc = "$out/share/doc";
        share = "$out/share";
        etc = "$out/etc";
      };

      defaultVars = globalVariables // {
        with-test = "$doCheck";
        with-doc = false;
        dev = false;
      };
      #// pkgVarsFor "ocaml" deps.ocaml.passthru.vars;

      pkgVars = vars: pkgVarsFor "_" vars // pkgVarsFor name vars;

      setFallbackDepVars = setVars (foldl recursiveUpdate { }
        (map (name: pkgVarsFor name (fallbackPackageVars name))
          (collectAllDeps (pkgdef.depends or [ ] ++ pkgdef.depopts or [ ]))));

      hashes = if pkgdef.url ? checksum then
        if isList pkgdef.url.checksum then
          getHashes pkgdef.url.checksum
        else
          getHashes [ pkgdef.url.checksum ]
      else
        { };

      externalPackages = import ./overlays/external.nix deps.nixpkgs;

      good-depexts = optionals (pkgdef ? depexts && (! isList pkgdef.depexts || ! isList (head pkgdef.depexts))) pkgdef.depexts;

      extInputNames = concatMap val (
        (relevantDepends versionResolutionVars
          (normalize good-depexts)));

      extInputs =
        map (x: if isString (val x) then externalPackages.${val x} else null)
        extInputNames;

      archive = pkgdef.url.src or pkgdef.url.archive or "";
      src = if pkgdef ? url then
      # Default unpacker doesn't support .zip
        if hashes == { } then
          builtins.fetchTarball archive
        else
          deps.nixpkgs.fetchurl ({ url = archive; } // hashes)
      else
        pkgdef.src or emptyDirectory;

      fake-opam = writeShellScriptBin "opam" ''
        while [[ $# -gt 0 ]]; do
          if [[ "$1" == config ]] || [[ "$1" == var ]] || [[ "$1" == "--*" ]]; then
            shift
          else
            varName="opam__''${''${1//:/__}//-/_}"
            printf "%s" "$(eval echo '$'"$varName")"
            break
          fi
        done
      '';

      opam-subst = writeShellScript "opam-subst" ''
        set -euo pipefail
        evalOpamVar() {
          contents="''${1:2:-2}"
          var="''${contents%\?*}"
          var_minus_underscores="''${var//-/_}"
          var_plus_underscores="''${var//+/_}"
          varname="opam__''${var_plus_underscores//:/__}"
          options="''${contents#*\?}"
          if [[ ! "$options" == "$var" ]]; then
            if [[ "$(eval echo ' ''${'"$varname"'-null}')" == true ]]; then
              printf '%s' "''${options%:*}"
            else
              printf '%s' "''${options#*:}"
            fi
          else
            printf '%s' "$(eval echo '$'"$varname")"
          fi
        }
        cp "$1" /tmp/opam-subst
        for subst in $(grep -o '%{[a-zA-Z0-9_:?+-]*}%' "$1"); do
          sed -e "s/$subst/$(evalOpamVar "$subst")/" -i /tmp/opam-subst
        done
        sed -e 's/%%/%/g' /tmp/opam-subst > "$2"
      '';

      messages = filter isString (relevantDepends versionResolutionVars
        (pkgdef.messages or [ ] ++ pkgdef.post-messages or [ ]));

      traceAllMessages = val:
        foldl' (acc: x: trace "${name}: ${x}" acc) val messages;

      pkg = stdenv.mkDerivation ({
        pname = traceAllMessages name;
        inherit version;

        buildInputs = extInputs ++ ocamlInputs;

        doCheck = false;

        inherit src;

        nativeBuildInputs = extInputs ++ ocamlInputs
          ++ optional (deps ? dune) fake-opam
          ++ optional (hasSuffix ".zip" archive) unzip;
        # Dune uses `opam var prefix` to get the prefix, which we want set to $out

        configurePhase = ''
          runHook preConfigure
          ${optionalString (pkgdef ? files) "cp -R ${pkgdef.files}/* ."}
          if [[ -z $dontPatchShebangsEarly ]]; then patchShebangs .; fi
          export opam__ocaml__version="''${opam__ocaml__version-${deps.ocaml.version}}"
          source ${
            toFile "set-vars.sh" (setVars (defaultVars // pkgVars vars // vars
              // stubOutputs // deps.extraVars or { }))
          }
          source ${toFile "set-fallback-vars.sh" setFallbackDepVars}
          ${setEnv pkgdef.build-env or [ ]}
          ${concatMapStringsSep "\n" (subst:
            "${opam-subst} ${escapeShellArg subst}.in ${escapeShellArg subst}")
          (concatLists (normalize' pkgdef.substs or [ ]))}
          ${concatMapStringsSep "\n" (patch: "patch -p1 ${patch}")
          (concatLists (normalize' pkgdef.substs or [ ]))}
          export OCAMLTOP_INCLUDE_PATH="$OCAMLPATH"
          export OCAMLFIND_DESTDIR="$out/lib/ocaml/''${opam__ocaml__version}/site-lib"
          export OPAM_PACKAGE_NAME="$pname"
          OPAM_PACKAGE_NAME_="''${pname//-/_}"
          export OPAM_PACKAGE_NAME_="''${OPAM_PACKAGE_NAME_//+/_}"
          export OPAM_PACKAGE_VERSION="$version"
          runHook postConfigure
        '';

        buildPhase = ''
          runHook preBuild
          ${evalSection pkgdef.build or [ ]}
          runHook postBuild
        '';

        # TODO: get rid of opam-installer and do everything with opam2json
        installPhase = ''
          runHook preInstall
          # Some installers expect the installation directories to be present
          mkdir -p "$OCAMLFIND_DESTDIR" "$out/bin"
          ${evalSection pkgdef.install or [ ]}
          if [[ -e "''${pname}.install" ]]; then
          ${opam-installer}/bin/opam-installer "''${pname}.install" --prefix="$out" --libdir="$OCAMLFIND_DESTDIR"
          fi
          runHook postInstall
        '';

        preFixupPhases =
          [ "fixDumbPackagesPhase" "nixSupportPhase" "cleanupPhase" ];

        fixDumbPackagesPhase = ''
          # Some packages like to install to %{prefix}%/lib instead of %{lib}%
          if [[ -e "$out/lib/''${pname}/META" ]] && [[ ! -e "$OCAMLFIND_DESTDIR/''${pname}" ]]; then
            mv "$out/lib/''${pname}" "$OCAMLFIND_DESTDIR"
          fi
          # Some packages like to install to %{libdir}% instead of %{libdir}%/%{name}%
          if [[ ! -d "$OCAMLFIND_DESTDIR/''${pname}" ]] && [[ -e "$OCAMLFIND_DESTDIR/META" ]]; then
            mv "$OCAMLFIND_DESTDIR" "$NIX_BUILD_TOP/destdir"
            mkdir -p "$OCAMLFIND_DESTDIR"
            mv "$NIX_BUILD_TOP/destdir" "$OCAMLFIND_DESTDIR/''${pname}"
          fi
        '';

        nixSupportPhase = ''
          mkdir -p "$out/nix-support"

          touch "$out/nix-support/is-opam-nix-package"

          # Ocaml packages may expect that all their transitive dependencies are present :(
          # Propagate all our buildInputs, and all propagated inputs of our buildInputs.
          for input in $buildInputs $propagatedBuildInputs; do
            printf "$input\n"
            [ -f "$input/nix-support/is-opam-nix-package" ] || continue
            for subinput in $(cat "$input/nix-support/propagated-build-inputs"); do
              printf "$subinput\n"
            done
          done | sort | uniq | xargs > "$out/nix-support/propagated-build-inputs"

          for input in $nativeBuildInputs; do
            printf "$input\n"
            [ -f "$input/nix-support/is-opam-nix-package" ] || continue
            for subinput in $(cat "$input/nix-support/propagated-native-build-inputs"); do
              printf "$subinput\n"
            done
          done | sort | uniq | xargs > "$out/nix-support/propagated-native-build-inputs"

          env | grep "^opam__''${OPAM_PACKAGE_NAME_}__[a-zA-Z0-9_]*=" | sed 's/^/export /' > "$out/nix-support/setup-hook"

          if [[ -d "$OCAMLFIND_DESTDIR" ]]; then
            printf '%s%s\n' ${
              escapeShellArg "export OCAMLPATH=\${OCAMLPATH-}\${OCAMLPATH:+:}"
            } "$OCAMLFIND_DESTDIR" >> $out/nix-support/setup-hook
          fi
          if [[ -d "$OCAMLFIND_DESTDIR/stublibs" ]]; then
            printf '%s%s\n' ${
              escapeShellArg
              "export CAML_LD_LIBRARY_PATH=\${CAML_LD_LIBRARY_PATH-}\${CAML_LD_LIBRARY_PATH:+:}"
            } "$OCAMLFIND_DESTDIR/stublibs" >> "$out/nix-support/setup-hook"
          fi
          printf '%s\n' ${
            escapeShellArg (setEnv pkgdef.set-env or [ ])
          } >> "$out/nix-support/setup-hook"

          if [[ -f "''${pname}.config" ]]; then
            eval "$(${opam2json}/bin/opam2json "''${pname}.config" | ${jq}/bin/jq \
            '.variables | to_entries | .[] | "echo export "+(("opam__"+env["pname"]+"__"+.key) | gsub("[+-]"; "_"))+"="+(.value | tostring)' -r)" \
            >> "$out/nix-support/setup-hook"
          fi
        '';

        cleanupPhase = ''
          if [ -e "$out/bin" ] && ! ls -1qA "$out/bin" | grep -q .; then
            rm -d "$out/bin"
          fi
          if [ -e "$OCAMLFIND_DESTDIR" ] && ! ls -1qA "$OCAMLFIND_DESTDIR" | grep -q .; then
            rm -d "$OCAMLFIND_DESTDIR"
            rm -d "$out/lib/ocaml/''${opam__ocaml__version}"
            if ! ls -1qA "$out/lib/ocaml" | grep -q .; then
              rm -rf "$out/lib/ocaml"
              if ! ls -1qA "$out/lib" | grep -q .; then
                rm -rf "$out/lib"
              fi
            fi
          fi
        '';

        passthru = { pkgdef = pkgdef; };
      });
    in pkg;

}
