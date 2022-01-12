lib:

let
  inherit (builtins)
    isString isList isBool isInt concatMap toJSON head filter concatLists foldl'
    trace toFile readDir replaceStrings;
  inherit (lib)
    optional hasSuffix optionalString concatMapStringsSep foldl mapAttrs
    optionals recursiveUpdate escapeShellArg;

  inherit (import ./opam-evaluator.nix lib)
    compareVersions' collectAllValuesFromOptionList val functionArgsFor
    filterOptionList pkgVarsFor varsToShell filterSectionInShell normalize
    normalize' getHashes envToShell;

  alwaysNative = import ./always-native.nix;

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
    ocaml = true;
  } // functionArgsFor pkgdef;

  __functor = self: deps:
    let
      inherit (deps.nixpkgs) stdenv;
      inherit (deps.nixpkgs.pkgsBuildBuild)
        envsubst writeText writeShellScriptBin writeShellScript unzip
        emptyDirectory opam-installer jq opam2json;

      globalVariables = import ./global-variables.nix stdenv.hostPlatform;
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
        pinned = true;
        dev = pkgdef ? src;
        version = pkgdef.version;
        _ = pkgdef;
        ${name} = pkgdef;
      } // (mapAttrs (name: dep: dep.version or null) deps)
        // deps.extraVars or { };

      dependsNames =
        filterOptionList versionResolutionVars pkgdef.depends or [ ];
      depoptsNames =
        filterOptionList versionResolutionVars pkgdef.depopts or [ ];

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
        dev = pkgdef ? src;
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
        dev = pkgdef ? src;
      };
      #// pkgVarsFor "ocaml" deps.ocaml.passthru.vars;

      pkgVars = vars: pkgVarsFor "_" vars // pkgVarsFor name vars;

      setFallbackDepVars = varsToShell (foldl recursiveUpdate { }
        (map (name: pkgVarsFor name (fallbackPackageVars name))
          (collectAllValuesFromOptionList
            (pkgdef.depends or [ ] ++ pkgdef.depopts or [ ]))));

      hashes = if pkgdef.url ? checksum then
        if isList pkgdef.url.checksum then
          getHashes pkgdef.url.checksum
        else
          getHashes [ pkgdef.url.checksum ]
      else
        { };

      externalPackages = if (readDir ./overlays/external)
      ? "${globalVariables.os-distribution}.nix" then
        import
        (./overlays/external + "/${globalVariables.os-distribution}.nix")
        deps.nixpkgs
      else
        trace "Depexts are not supported on ${globalVariables.os-distribution}"
        { };

      good-depexts = optionals (pkgdef ? depexts
        && (!isList pkgdef.depexts || !isList (head pkgdef.depexts)))
        pkgdef.depexts;

      extInputNames = concatMap val
        ((filterOptionList versionResolutionVars (normalize good-depexts)));

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

      evalOpamVar = ''
        evalOpamVar() {
          contents="''${1:2:-2}"
          var="''${contents%\?*}"
          var_minus_underscores="''${var//-/_}"
          var_plus_underscores="''${var_minus_underscores//+/_}"
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
      '';
      fake-opam = writeShellScriptBin "opam" ''
        ${evalOpamVar}
        while [[ $# -gt 0 ]]; do
          if [[ "$1" == config ]] || [[ "$1" == var ]] || [[ "$1" == "--*" ]]; then
            shift
          else
            printf "%s\n" "$(evalOpamVar "$1")"
            break
          fi
        done
      '';

      opam-subst = writeShellScript "opam-subst" ''
        set -euo pipefail
        ${evalOpamVar}
        cp --no-preserve=all "$1" /tmp/opam-subst
        for subst in $(grep -o '%{[a-zA-Z0-9_:?+-]*}%' "$1"); do
          sed -e "s@$subst@$(evalOpamVar "$subst")@" -i /tmp/opam-subst
        done
        sed -e 's/%%/%/g' /tmp/opam-subst > "$2"
      '';

      messages = filter isString (filterOptionList versionResolutionVars
        (pkgdef.messages or [ ] ++ pkgdef.post-messages or [ ]));

      traceAllMessages = val:
        foldl' (acc: x: trace "${name}: [1m${x}[0m" acc) val messages;

      pkg = stdenv.mkDerivation ({
        pname = traceAllMessages name;
        version = replaceStrings ["~"] ["_"] version;

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
            toFile "set-vars.sh" (varsToShell (defaultVars // pkgVars vars
              // vars // stubOutputs // deps.extraVars or { }))
          }
          source ${toFile "set-fallback-vars.sh" setFallbackDepVars}
          ${envToShell pkgdef.build-env or [ ]}
          ${concatMapStringsSep "\n" (subst:
            "${opam-subst} ${escapeShellArg subst}.in ${escapeShellArg subst}")
          (concatLists (normalize' pkgdef.substs or [ ]))}
          ${concatMapStringsSep "\n" (patch: "patch -p1 ${patch}")
          (concatLists (normalize' pkgdef.patches or [ ]))}
          ${if compareVersions' "geq" deps.ocaml.version "4.08" then
            ''export OCAMLTOP_INCLUDE_PATH="$OCAMLPATH"''
          else ''
            for i in $(sed 's/:/ /g' <<< "$OCAMLPATH"); do
              [ -e "$i" ] && OCAMLPARAM=''${OCAMLPARAM-}''${OCAMLPARAM+,}I=$i
            done
            [ -n "$OCAMLPARAM" ] && export OCAMLPARAM=''${OCAMLPARAM},_
          ''}
          export OCAMLFIND_DESTDIR="$out/lib/ocaml/''${opam__ocaml__version}/site-lib"
          export OPAM_PACKAGE_NAME="$pname"
          OPAM_PACKAGE_NAME_="''${pname//-/_}"
          export OPAM_PACKAGE_NAME_="''${OPAM_PACKAGE_NAME_//+/_}"
          export OPAM_PACKAGE_VERSION="$version"
          runHook postConfigure
        '';

        buildPhase = ''
          runHook preBuild
          ${filterSectionInShell pkgdef.build or [ ]}
          runHook postBuild
        '';

        # TODO: get rid of opam-installer and do everything with opam2json
        installPhase = ''
          runHook preInstall
          # Some installers expect the installation directories to be present
          mkdir -p "$OCAMLFIND_DESTDIR" "$out/bin"
          ${filterSectionInShell pkgdef.install or [ ]}
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
          done | sort | uniq | sed 's/$/ /g' > "$out/nix-support/propagated-build-inputs"

          for input in $nativeBuildInputs; do
            printf "$input\n"
            [ -f "$input/nix-support/is-opam-nix-package" ] || continue
            for subinput in $(cat "$input/nix-support/propagated-native-build-inputs"); do
              printf "$subinput\n"
            done
          done | sort | uniq | sed 's/$/ /g' > "$out/nix-support/propagated-native-build-inputs"

          exportIfUnset() {
            sed -Ee 's/^([^=]*)=(.*)$/export \1="''${\1-\2}"/'
          }

          env | grep "^opam__''${OPAM_PACKAGE_NAME_}__[a-zA-Z0-9_]*=" | exportIfUnset > "$out/nix-support/setup-hook"

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
            escapeShellArg (envToShell pkgdef.set-env or [ ])
          } >> "$out/nix-support/setup-hook"

          if [[ -f "''${pname}.config" ]]; then
            eval "$(${opam2json}/bin/opam2json "''${pname}.config" | ${jq}/bin/jq \
            '.variables | to_entries | .[] | "echo "+(("opam__"+env["pname"]+"__"+.key) | gsub("[+-]"; "_"))+"="+(.value | tostring)' -r)" \
            | exportIfUnset \
            >> "$out/nix-support/setup-hook"
          fi
        '';

        cleanupPhase = ''
          pushd "$out"
          rmdir -p "bin" || true
          rmdir -p "$OCAMLFIND_DESTDIR" || true
          popd
          for var in $(env | cut -d= -f1 | grep opam__); do
            unset -- "$var"
          done
        '';

        passthru = { pkgdef = pkgdef; };
      });
    in pkg;

}
