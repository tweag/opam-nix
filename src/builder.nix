lib:

let
  inherit (builtins)
    isString isList isBool isInt concatMap toJSON head filter concatLists foldl'
    trace toFile readDir replaceStrings concatStringsSep attrValues;
  inherit (lib)
    optional hasSuffix optionalString concatMapStringsSep foldl mapAttrs
    optionals recursiveUpdate escapeShellArg warn;

  inherit (import ./evaluator lib)
    setup compareVersions' collectAllValuesFromOptionList val functionArgsFor
    filterOptionList pkgVarsFor varsToShell filterSectionInShell normalize
    normalize' getHashes envToShell getUrl;

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
        opam-installer jq opam2json removeReferencesTo;

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

      ocamlInputs = map (x:
        deps.${val x} or (lib.warn
          "[opam-nix] ${name}: missing required dependency: ${val x}" null))
        dependsNames ++ map (x:
          deps.${val x} or (trace
            "[opam-nix] ${name}: missing optional dependency ${val x}" null))
        depoptsNames;

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

      externalPackages = if (readDir ./overlays/external)
      ? "${globalVariables.os-distribution}.nix" then
        import (./overlays/external + "/${globalVariables.os-distribution}.nix")
        deps.nixpkgs
      else
        warn
        "[opam-nix] Depexts are not supported on ${globalVariables.os-distribution}"
        { };

      good-depexts = optionals (pkgdef ? depexts
        && (!isList pkgdef.depexts || !isList (head pkgdef.depexts)))
        pkgdef.depexts;

      extInputNames = concatMap val
        ((filterOptionList versionResolutionVars (normalize good-depexts)));

      extInputs = map (x:
        let v = val x;
        in if isString v then
          externalPackages.${v} or (warn ''
            [opam-nix] External dependency ${v} of package ${name}.${version} is missing.
            Please, add it to the file <opam-nix>/overlays/external/${globalVariables.os-distribution}.nix and make a pull request with your change.
            In the meantime, you can manually add the dependency to buildInputs/nativeBuildInputs of your derivation with overrideAttrs.
          '' null)
        else
          null) extInputNames;

      inherit (getUrl deps.nixpkgs pkgdef) archive src;

      evalOpamVar = ''
        evalOpamVar() {
          contents="''${1%*\}\%}"
          contents="''${contents//\%\{}"
          var="''${contents%\?*}"
          var_minus_underscores="''${var//-/_}"
          var_plus_underscores="''${var_minus_underscores//+/_}"
          var_dot_underscores="''${var_minus_underscores//./_}"
          varname="opam__''${var_dot_underscores//:/__}"
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

      opamSubst = ''
        opamSubst() {
          printf "Substituting %s to %s\n" "$1" "$2" > /dev/stderr
          TEMP="/tmp/opam-subst-$RANDOM$RANDOM$RANDOM"
          cp --no-preserve=all "$1" "$TEMP"
          substs="$(grep -o '%{[a-zA-Z0-9_:?+-]*}%' "$1")"
          shopt -u nullglob
          for subst in $substs; do
            var="$(echo "$subst")"
            sed -e "s@$var@$(evalOpamVar "$var")@" -i "$TEMP"
          done
          shopt -s nullglob
          sed -e 's/%%/%/g' "$TEMP" > "$2"
          rm "$TEMP"
        }
      '';

      prepareEnvironment = ''
        opam__ocaml__version="''${opam__ocaml__version-${deps.ocaml.version}}"
        source ${
          toFile "set-vars.sh" (varsToShell (defaultVars // pkgVars vars
            // vars // stubOutputs // deps.extraVars or { }))
        }
        source ${toFile "set-fallback-vars.sh" setFallbackDepVars}
        ${envToShell pkgdef.build-env or [ ]}
        ${evalOpamVar}
        ${opamSubst}
      '';

      # Some packages shell out to opam to do things. It's not great, but we need to work around that.
      fake-opam = deps.nixpkgs.writeShellScriptBin "opam" ''
        set -euo pipefail
        sourceRoot=""
        ${prepareEnvironment}
        bailArgs() {
          echo -e "\e[31;1mopam-nix fake opam doesn't understand these arguments: $@\e[0;0m" 1>&2
          exit 1
        }
        case "$1" in
          --version) echo "2.0.0";;
          config)
            case "$2" in
              var) evalOpamVar "$3"; echo;;
              subst) opamSubst "$3.in" "$3";;
              *) bailArgs "$@";;
            esac;;
          var) evalOpamVar "$2";;
          *) bailArgs;;
        esac
      '';

      messages = filter isString (filterOptionList versionResolutionVars
        (concatLists ((normalize' pkgdef.messages or [ ])
          ++ (normalize' pkgdef.post-messages or [ ]))));

      traceAllMessages = val:
        foldl' (acc: x: trace "[opam-nix] ${name}: [1m${x}[0m" acc) val
        messages;

      fetchExtraSources = concatStringsSep "\n" (attrValues (mapAttrs (name:
        { src, checksum }:
        "cp ${
          deps.nixpkgs.fetchurl
          ({ url = src; } // getHashes (head (normalize' checksum)))
        } ${escapeShellArg name}") pkgdef.extra-source or { }));

      pkg = stdenv.mkDerivation ({
        pname = traceAllMessages name;
        version = replaceStrings [ "~" ] [ "_" ] version;

        buildInputs = extInputs ++ ocamlInputs;

        nativeBuildInputs = extInputs ++ ocamlInputs
          ++ [ fake-opam ]
          ++ optional (hasSuffix ".zip" archive) unzip;

        strictDeps = true;

        doCheck = false;

        inherit src;

        prePatch = ''
          ${prepareEnvironment}
          ${optionalString (pkgdef ? files) "cp -R ${pkgdef.files}/* ."}
          ${fetchExtraSources}
          for subst in ${
            toString (map escapeShellArg (concatLists
              ((normalize' pkgdef.patches or [ ])
                ++ (normalize' pkgdef.substs or [ ]))))
          }; do
            if [[ -f "$subst".in ]]; then
              opamSubst "$subst.in" "$subst"
            fi
          done
        '';

        patches = normalize pkgdef.patches or [ ];

        configurePhase = ''
          runHook preConfigure
          if [[ -z $dontPatchShebangsEarly ]]; then patchShebangs .; fi
          ${if compareVersions' "geq" deps.ocaml.version "4.08" then
            ''export OCAMLTOP_INCLUDE_PATH="$OCAMLPATH"''
          else ''
            for i in $(sed 's/:/ /g' <<< "$OCAMLPATH"); do
              [ -e "$i" ] && OCAMLPARAM=''${OCAMLPARAM-}''${OCAMLPARAM+,}I=$i
            done
            [ -n "$OCAMLPARAM" ] && export OCAMLPARAM=''${OCAMLPARAM},_
          ''}
          ${optionalString deps.nixpkgs.stdenv.cc.isClang
          ''export NIX_CFLAGS_COMPILE="''${NIX_CFLAGS_COMPILE-} -Wno-error"''}
          export OCAMLFIND_DESTDIR="$out/lib/ocaml/''${opam__ocaml__version}/site-lib"
          export OPAM_PACKAGE_NAME="$pname"
          OPAM_PACKAGE_NAME_="''${pname//-/_}"
          export OPAM_PACKAGE_NAME_="''${OPAM_PACKAGE_NAME_//+/_}"
          export OPAM_PACKAGE_VERSION="$version"
          export OPAM_SWITCH_PREFIX="$out"
          source "${setup}"
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
          mkdir -p "$OCAMLFIND_DESTDIR" "$OCAMLFIND_DESTDIR/stublibs" "$out/bin"
          ${filterSectionInShell pkgdef.install or [ ]}
          if [[ -e "''${pname}.install" ]]; then
          ${opam-installer}/bin/opam-installer "''${pname}.install" --prefix="$out" --libdir="$OCAMLFIND_DESTDIR"
          fi
          runHook postInstall
        '';

        preFixupPhases = [
          "fixDumbPackagesPhase"
          "nixSupportPhase"
          "cleanupPhase"
          "removeOcamlReferencesPhase"
        ];

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

        doNixSupport = true;
        propagateInputs = true;
        exportSetupHook = true;

        nixSupportPhase = ''
          if [[ -n "$doNixSupport" ]]; then
            mkdir -p "$out/nix-support"

            touch "$out/nix-support/is-opam-nix-package"

            if [[ -n "$propagateInputs" ]]; then
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
            fi

            if [[ -n "$exportSetupHook" ]]; then
              exportIfUnset() {
                sed -Ee 's/^([^=]*)=(.*)$/\1="''${\1-\2}"/'
              }

              ( set -o posix; set ) | grep "^opam__''${OPAM_PACKAGE_NAME_}__[a-zA-Z0-9_]*=" | exportIfUnset > "$out/nix-support/setup-hook"

              if [[ -d "$OCAMLFIND_DESTDIR" ]]; then
                printf '%s%s\n' ${
                  escapeShellArg
                  "export OCAMLPATH=\${OCAMLPATH-}\${OCAMLPATH:+:}"
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
            fi
          fi
        '';

        cleanupPhase = ''
          pushd "$out"
          rmdir -p "bin" 2>/dev/null || true
          rmdir -p "$OCAMLFIND_DESTDIR/stublibs" 2>/dev/null || true
          rmdir -p "$OCAMLFIND_DESTDIR" 2>/dev/null || true
          popd
          for var in $(printenv | grep -o '^opam__'); do
            unset -- "''${var//=*}"
          done
        '';

        removeOcamlReferences = false;

        removeOcamlReferencesPhase = ''
          if [[ -n "$removeOcamlReferences" ]] && [[ -d "$out/bin" ]] && command -v ocamlc; then
            echo "Stripping out references to ocaml compiler in binaries"
            ${removeReferencesTo}/bin/remove-references-to -t "$(dirname "$(dirname "$(command -v ocamlc)")")" $out/bin/*
          fi
        '';

        passthru = { pkgdef = pkgdef; };
      });
    in pkg;

}
