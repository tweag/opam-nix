lib:

let
  inherit (builtins)
    isString
    isList
    head
    filter
    foldl'
    trace
    toFile
    readDir
    replaceStrings
    concatStringsSep
    attrValues
    ;
  inherit (lib)
    optional
    hasSuffix
    optionalString
    foldl
    mapAttrs
    recursiveUpdate
    escapeShellArg
    warn
    flatten
    ;

  inherit (import ./evaluator lib)
    setup
    compareVersions'
    collectAllValuesFromList
    functionArgsFor
    filterPackageFormula
    filterList
    pkgVarsFor
    varsToShell
    filterSectionInShell
    getHashes
    envToShell
    getUrl
    ;

  fallbackPackageVars = name: {
    inherit name;
    installed = "false";
    enable = "disable";
    version = "";
  };
in
originalPkgdef: resolveEnv: {

  __functionArgs = {
    extraDeps = true;
    extraVars = true;
    nixpkgs = false;
    buildPackages = false;

    opam-installer = true;
    ocaml = true;
  } // functionArgsFor originalPkgdef;

  __functor =
    self: deps:
    deps.nixpkgs.stdenv.mkDerivation (
      fa:
      let
        inherit (deps.nixpkgs.pkgsBuildBuild)
          unzip
          opam-installer
          jq
          opam2json
          removeReferencesTo
          ;

        inherit (fa.passthru) pkgdef;

        inherit (pkgdef) name version;

        globalVariables = (import ./global-variables.nix deps.nixpkgs.stdenv.hostPlatform) // resolveEnv;

        defaultVars = globalVariables // {
          with-test = fa.doCheck;
          with-doc = fa.doDoc;
          dev = pkgdef ? src;
          build = true;
          post = false;
          pinned = true;
        };

        versionResolutionVars =
          pkgdef
          // defaultVars
          // {
            _ = pkgdef;
            ${name} = pkgdef;
          }
          // (mapAttrs (name: dep: dep.passthru.pkgdef.version or dep.version or null) deps)
          // deps.extraVars or { };

        # https://opam.ocaml.org/doc/Manual.html#opamfield-patches
        patches = filterList versionResolutionVars pkgdef.patches or [ ];

        # https://opam.ocaml.org/doc/Manual.html#opamfield-substs
        substs = filterList versionResolutionVars pkgdef.substs or [ ];

        # https://opam.ocaml.org/doc/Manual.html#opamfield-depends
        depends = filterPackageFormula versionResolutionVars pkgdef.depends or [ ];

        # https://opam.ocaml.org/doc/Manual.html#opamfield-depopts
        depopts = filterPackageFormula versionResolutionVars pkgdef.depopts or [ ];

        ocamlInputs =
          map (
            x: deps.${x} or (lib.warn "[opam-nix] ${name}: missing required dependency: ${x}" null)
          ) depends
          ++ map (
            x: deps.${x} or (trace "[opam-nix] ${name}: missing optional dependency ${x}" null)
          ) depopts;

        stubOutputs = {
          build = "$NIX_BUILD_TOP/$sourceRoot";
        };

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

        #// pkgVarsFor "ocaml" deps.ocaml.passthru.vars;

        pkgVars = vars: pkgVarsFor "_" vars // pkgVarsFor name vars;

        setFallbackDepVars = varsToShell (
          foldl recursiveUpdate { } (
            map (name: pkgVarsFor name (fallbackPackageVars name)) (
              collectAllValuesFromList pkgdef.depends or [ ]
              ++ collectAllValuesFromList pkgdef.depopts or [ ]
            )
          )
        );

        externalPackages =
          if (readDir ./overlays/external) ? "${globalVariables.os-distribution}.nix" then
            import (./overlays/external + "/${globalVariables.os-distribution}.nix") deps.nixpkgs
          else
            warn "[opam-nix] Depexts are not supported on ${globalVariables.os-distribution}" { };

        good-depexts =
          if (pkgdef ? depexts && (!isList pkgdef.depexts || !isList (head pkgdef.depexts))) then
            pkgdef.depexts
          else
            [ ];

        extInputNames = filterList versionResolutionVars good-depexts;

        extInputs = map (
          x:
          if isString x then
            externalPackages.${x} or (warn ''
              [opam-nix] External dependency ${x} of package ${name}.${version} is missing.
              Please, add it to the file <opam-nix>/overlays/external/${globalVariables.os-distribution}.nix and make a pull request with your change.
              In the meantime, you can manually add the dependency to buildInputs/nativeBuildInputs of your derivation with overrideAttrs.
            '' null)
          else
            null
        ) extInputNames;

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

        # Fake `opam list` using the `$OCAMLPATH` env var.
        # sed 1. split lines on ':'
        #  -> /nix/store/yw6nnn1v9cx22ibg4d5ba1ff0zapl8ys-dune-3.14.2/lib/ocaml/5.1.1/site-lib
        # sed 2. strip '/nix/store/...' prefix
        #  -> dune-3.14.2/lib/ocaml/5.1.1/site-lib
        # sed 3. strip '/lib/...' suffix
        #  -> dune-3.14.2
        opamFakeList = ''
          opamFakeList() {
            echo "$OCAMLPATH" \
              | sed 's/:/\n/g' \
              | sed 's:^/nix/store/[a-z0-9]*-::' \
              | sed 's:/.*$::' \
              | sort \
              | uniq
          }
          opamList() {
            echo -e '\e[31;1mopam-nix fake opam does not support "opam list"; for a human-readable package list, use "opam fake-list"\e[0;0m' 1>&2
          }
        '';

        opamSubst = ''
          opamSubst() {
            printf "Substituting %s to %s\n" "$1" "$2" 1>&2
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
        allEvalVars = defaultVars // pkgVars vars // vars // stubOutputs // deps.extraVars or { };

        prepareEnvironment = ''
          opam__ocaml__version="''${opam__ocaml__version-${deps.ocaml.version}}"
          source ${toFile "set-vars.sh" (varsToShell allEvalVars)}
          source ${toFile "set-fallback-vars.sh" setFallbackDepVars}
          ${envToShell pkgdef.build-env or [ ]}
          ${evalOpamVar}
          ${opamSubst}
          ${opamFakeList}
        '';

        # Some packages shell out to opam to do things. It's not great, but we need to work around that.
        fake-opam = deps.nixpkgs.writeShellScriptBin "opam" ''
          set -euo pipefail
          sourceRoot=""
          ${prepareEnvironment}
          args="$@"
          bailArgs() {
            echo -e "\e[31;1mopam-nix fake opam doesn't understand these arguments: $args\e[0;0m" 1>&2
            exit 1
          }
          case "$1" in
            --version) echo "2.0.0";;
            config)
              case "$2" in
                var) evalOpamVar "$3"; echo;;
                subst) opamSubst "$3.in" "$3";;
                *) bailArgs;;
              esac;;
            list) opamList;;
            fake-list) opamFakeList;;
            var) evalOpamVar "$2";;
            switch)
              case "$3" in
                show) echo "default";;
                *) bailArgs;;
              esac;;
            exec)
              shift
              if [[ "x$1" == "x--" ]]; then
                shift
                exec "$@"
              else
                exec "$@"
              fi;;
            *) bailArgs;;
          esac
        '';

        # https://opam.ocaml.org/doc/Manual.html#opamfield-messages
        # https://opam.ocaml.org/doc/Manual.html#opamfield-post-messages
        messages = filter isString (
          filterList versionResolutionVars (flatten [
            pkgdef.messages or [ ]
            pkgdef.post-messages or [ ]
          ])
        );

        traceAllMessages = val: foldl' (acc: x: trace "[opam-nix] ${name}: [1m${x}[0m" acc) val messages;

        # https://opam.ocaml.org/doc/Manual.html#opamsection-extra-sources
        fetchExtraSources = concatStringsSep "\n" (
          attrValues (
            mapAttrs (
              name:
              { src, checksum }:
              "cp ${
                deps.nixpkgs.fetchurl (
                  {
                    url = src;
                  }
                  // getHashes (if isList checksum then checksum else [ checksum ])
                )
              } ${escapeShellArg name}"
            ) pkgdef.extra-source.section or { }
          )
        );

        bz2Unpacker = deps.nixpkgs.writeTextFile {
          name = "bz2-unpacker";
          text = ''
            unpackCmdHooks+=(_tryBz2)
            _tryBz2() {
              if ! [[ "$curSrc" =~ \.bz2$ ]]; then return 1; fi

              tar xf "$curSrc" --mode=+w --warning=no-timestamp
            }
          '';
          destination = "/nix-support/setup-hook";
        };

      in
      {
        pname = traceAllMessages name;
        version = replaceStrings [ "~" ] [ "_" ] version;

        OPAM_PACKAGE_NAME = name;
        OPAM_PACKAGE_VERSION = version;

        buildInputs = extInputs ++ ocamlInputs;

        withFakeOpam = true;

        nativeBuildInputs =
          extInputs
          ++ ocamlInputs
          ++ optional fa.withFakeOpam [ fake-opam ]
          ++ optional (hasSuffix ".zip" archive) unzip
          ++ optional (hasSuffix ".bz2" archive) bz2Unpacker;

        strictDeps = true;

        doCheck = false;
        doDoc = false;

        inherit src;

        # https://opam.ocaml.org/doc/Manual.html#opamfield-extra-files
        prePatch = ''
          ${prepareEnvironment}
          ${optionalString (pkgdef ? files) "cp -R ${pkgdef.files}/* ."}
          ${fetchExtraSources}
          for subst in ${toString (map escapeShellArg (patches ++ substs))}; do
            if [[ -f "$subst".in ]]; then
              opamSubst "$subst.in" "$subst"
            fi
          done
        '';

        inherit patches;

        configurePhase = ''
          runHook preConfigure
          if [[ -z $dontPatchShebangsEarly ]]; then patchShebangs .; fi
          ${
            if compareVersions' "geq" deps.ocaml.version "4.08" then
              ''export OCAMLTOP_INCLUDE_PATH="$OCAMLPATH"''
            else
              ''
                for i in $(sed 's/:/ /g' <<< "$OCAMLPATH"); do
                  [ -e "$i" ] && OCAMLPARAM=''${OCAMLPARAM-}''${OCAMLPARAM+,}I=$i
                done
                [ -n "$OCAMLPARAM" ] && export OCAMLPARAM=''${OCAMLPARAM},_
              ''
          }
          ${optionalString deps.nixpkgs.stdenv.cc.isClang ''export NIX_CFLAGS_COMPILE="''${NIX_CFLAGS_COMPILE-} -Wno-error"''}
          export OCAMLFIND_DESTDIR="$out/lib/ocaml/''${opam__ocaml__version}/site-lib"
          export OCAMLLIBDIR="$OCAMLFIND_DESTDIR"
          OPAM_PACKAGE_NAME_="''${OPAM_PACKAGE_NAME//-/_}"
          export OPAM_PACKAGE_NAME_="''${OPAM_PACKAGE_NAME_//+/_}"
          export OPAM_PACKAGE_NAME
          export OPAM_PACKAGE_VERSION
          export OPAM_SWITCH_PREFIX="$out"
          source "${setup}"
          runHook postConfigure
        '';

        # https://opam.ocaml.org/doc/Manual.html#opamfield-build
        buildPhase = ''
          runHook preBuild
          ${filterSectionInShell pkgdef.build or [ ]}
          runHook postBuild
        '';

        # TODO: get rid of opam-installer and do everything with opam2json
        # https://opam.ocaml.org/doc/Manual.html#opamfield-install
        installPhase = ''
          runHook preInstall
          # Some installers expect the installation directories to be present
          mkdir -p "$OCAMLFIND_DESTDIR" "$OCAMLFIND_DESTDIR/stublibs" "$out/bin" "$out/share/man/man"{1,2,3,4,5,6,7,8,9}
          ${filterSectionInShell pkgdef.install or [ ]}
          if [[ -e "''${OPAM_PACKAGE_NAME}.install" ]]; then
          ${opam-installer}/bin/opam-installer "''${OPAM_PACKAGE_NAME}.install" --prefix="$out" --libdir="$OCAMLFIND_DESTDIR"
          fi
          runHook postInstall
        '';

        preFixupPhases = [
          "fixDumbPackagesPhase"
          "cleanupPhase"
          "nixSupportPhase"
          "removeOcamlReferencesPhase"
        ];

        fixDumbPackagesPhase = ''
          # Some packages like to install to %{prefix}%/lib instead of %{lib}%
          if [[ -e "$out/lib/''${OPAM_PACKAGE_NAME}/META" ]] && [[ ! -e "$OCAMLFIND_DESTDIR/''${OPAM_PACKAGE_NAME}" ]]; then
            mv "$out/lib/''${OPAM_PACKAGE_NAME}" "$OCAMLFIND_DESTDIR"
          fi
          # Some packages like to install to %{libdir}% instead of %{libdir}%/%{name}%
          if [[ ! -d "$OCAMLFIND_DESTDIR/''${OPAM_PACKAGE_NAME}" ]] && [[ -e "$OCAMLFIND_DESTDIR/META" ]]; then
            mv "$OCAMLFIND_DESTDIR" "$NIX_BUILD_TOP/destdir"
            mkdir -p "$OCAMLFIND_DESTDIR"
            mv "$NIX_BUILD_TOP/destdir" "$OCAMLFIND_DESTDIR/''${OPAM_PACKAGE_NAME}"
          fi
        '';

        doNixSupport = true;
        propagateInputs = true;
        exportSetupHook = true;

        cleanupPhase = ''
          pushd "$out"
          rmdir -p "bin" 2>/dev/null || true
          rmdir -p "$OCAMLFIND_DESTDIR/stublibs" 2>/dev/null || true
          rmdir -p "$OCAMLFIND_DESTDIR" 2>/dev/null || true
          rmdir -p "share/man/man*" 2>/dev/null || true
          rmdir -p "share/man" 2>/dev/null || true
          rmdir -p "share" 2>/dev/null || true
          popd
          for var in $(printenv | grep -o '^opam__'); do
            unset -- "''${var//=*}"
          done
        '';

        # https://opam.ocaml.org/doc/Manual.html#opamfield-setenv
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
                printf '%s%s\n' ${escapeShellArg "export OCAMLPATH=\${OCAMLPATH-}\${OCAMLPATH:+:}"} "$OCAMLFIND_DESTDIR" >> $out/nix-support/setup-hook
              fi
              if [[ -d "$OCAMLFIND_DESTDIR/stublibs" ]]; then
                printf '%s%s\n' ${escapeShellArg "export CAML_LD_LIBRARY_PATH=\${CAML_LD_LIBRARY_PATH-}\${CAML_LD_LIBRARY_PATH:+:}"} "$OCAMLFIND_DESTDIR/stublibs" >> "$out/nix-support/setup-hook"
              fi
              printf '%s\n' ${
                escapeShellArg (envToShell pkgdef.set-env.section or [ ])
              } >> "$out/nix-support/setup-hook"

              if [[ -f "''${OPAM_PACKAGE_NAME}.config" ]]; then
                ${opam2json}/bin/opam2json "''${OPAM_PACKAGE_NAME}.config" | ${jq}/bin/jq \
                  '.variables | select (. != null) | .section | to_entries | .[] | (("opam__"+env["OPAM_PACKAGE_NAME"]+"__"+.key) | gsub("[+-]"; "_"))+"="+(.value | tostring | gsub("'"'"'"; "'"\\\\'"'") | gsub("\""; "\\\""))' -r \
                | exportIfUnset \
                >> "$out/nix-support/setup-hook"
              fi
            fi
          fi
        '';

        removeOcamlReferences = false;

        removeOcamlReferencesPhase = ''
          if [[ -n "$removeOcamlReferences" ]] && [[ -d "$out/bin" ]] && command -v ocamlc; then
            echo "Stripping out references to ocaml compiler in binaries"
            ${removeReferencesTo}/bin/remove-references-to -t "$(dirname "$(dirname "$(command -v ocamlc)")")" $out/bin/*
          fi
        '';

        passthru = {
          pkgdef = originalPkgdef;
        };
      }
    );

}
