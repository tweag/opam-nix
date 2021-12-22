pkgs:
with builtins;
with pkgs.lib; rec {
  alwaysNative = import ./always-native.nix;

  globalVariables = import ./global-variables.nix pkgs;

  pkgdeftodrv = { name, version, ... }@pkgdef: rec {
    # { ${depName} = isOptional :: Bool; }
    # buildInputs and nativeBuildInputs must always be present, but checkInputs may be absent (e.g. when doCheck = false)
    deps-optional = listToAttrs (map (x: nameValuePair x false)
      (sortedDepNames.buildInputs ++ sortedDepNames.nativeBuildInputs)
      ++ (map (x: nameValuePair x true) sortedDepNames.checkInputs));

    val = x: x.val or x;

    hasOpt = opt: dep: any (x: opt == x.id or null) dep.options or [ ];

    # Either String StringWithOption -> String
    depType = dep:
      if hasOpt "with-test" dep then
        "checkInputs"
      else if builtins.elem (val dep) alwaysNative || hasOpt "build" dep then
        "nativeBuildInputs"
      else
        "buildInputs";

    fallbackPackageVars = name: {
      inherit name;
      installed = false;
      enable = "disable";
    };

    depends = filter (x: isString x || (x ? val && isString x.val))
      ((pkgdef.depends or [ ]) ++ (pkgdef.depopts or [ ]));

    # FIXME: There are more operators
    evalOp = op: vals:
      let
        fst = elemAt vals 0;
        snd = elemAt vals 1;
      in if op == "eq" then
        fst == snd
      else if op == "gt" then
        fst > snd
      else if op == "lt" then
        fst < snd
      else if op == "geq" then
        fst >= snd
      else if op == "leq" then
        fst <= snd
      else if op == "neq" then
        fst != snd
      else if op == "not" then
        !fst
      else if op == "and" then
        fst && snd
      else if op == "or" then
        fst || snd
      else
        throw "Operation ${op} not implemented";

    # "Sort" the depends into three categories
    # { buildInputs = [ String ]; checkInputs = [ String ]; nativeBuildInputs = [ String ] }
    sortedDepNames = (foldl mergeAttrsConcatenateValues {
      buildInputs = [ ];
      checkInputs = [ ];
      nativeBuildInputs = [ ];
    } (map (dep: { ${depType dep} = [ (val dep) ]; }) depends));

    __functionArgs = {
      extraDeps = true;
      extraVars = true;

      stdenv = false;
      fetchurl = true;
      opam-installer = true;
      ocamlfind = false;
    } // deps-optional;

    __functor = self: deps:
      with self;
      let
        sortedDeps = mapAttrs (_: map (x: deps.${x} or null)) sortedDepNames;

        packageDepends = removeAttrs deps [ "extraDeps" "extraVars" "stdenv" ];

        stubOutputs = {
          prefix = "$out";
          bin = "$out/bin";
          sbin = "$out/bin";
          lib = "$OCAMLFIND_DESTDIR/${name}";
          man = "$out/share/man";
          doc = "$out/share/doc";
          share = "$out/share";
          etc = "$out/etc";
        };

        vars = globalVariables // {
          with-test = true;
          with-doc = false;
        } // (mapAttrs (_: pkg: pkg.passthru.vars) packageDepends)
          // (deps.extraVars or { }) // rec {
            _ = passthru.vars // stubOutputs;
            ${name} = _;
          } // passthru.vars // stubOutputs;

        getVar = path:
          if hasAttrByPath path vars then
            getAttrFromPath path vars
          else if length path > 1 then
            getAttrFromPath (tail path) (fallbackPackageVars (head path))
          else
            null;

        evalValue = val:
          if val ? id then
            getVar (splitString ":" val.id)
          else if val ? op then
            evalOp val.op (map evalValue val.val)
          else if val ? options then
            if all (x: evalValue x != null && evalValue x) val.options then
              evalValue val.val
            else
              null
          else
            interpretStringsRec val;

        evalValueKeepOptions = val:
          {
            val = evalValue val;
          } // optionalAttrs (val ? options) { inherit (val) options; };

        evalCommandEntry = entry:
          let e = evalValue entry;
          in if isNull e then "" else e;

        renderCommand = command:
          concatMapStringsSep " " evalCommandEntry (val command);

        trySha256 = c:
          let m = match "sha256=(.*)" c;
          in if isNull m then [ ] else [{ sha256 = head m; }];
        trySha512 = c:
          let m = match "sha512=(.*)" c;
          in if isNull m then [ ] else [{ sha512 = head m; }];

        hashes = if pkgdef.url ? checksum && isList pkgdef.url.checksum then
          concatMap (x: trySha512 x ++ trySha256 x) pkgdef.url.checksum
        else
          [ ];

        interpretStringsRec = val:
          if isString val then
            interpretStringInterpolation val
          else if isList val then
            map interpretStringsRec val
          else if isBool val || isInt val then
            toString' val
          else
            val;

        toString' = v:
          if isString v then
            v
          else if isInt v then
            toString v
          else if isBool v then
            if v then "true" else "false"
          else if isNull v then
            ""
          else
            throw "oh nooo";

        interpretStringInterpolation = s:
          let
            pieces = filter isString (split "([%][{]|[}][%])" s);
            result = foldl ({ i, result }:
              piece: {
                i = !i;
                result = result + (if i then
                  toString' (evalValue { id = piece; })
                else
                  piece);
              }) {
                i = false;
                result = "";
              } pieces;
          in if length pieces == 1 then s else result.result;

        # FIXME do this for every section
        normalize = section:
          if !isList (val section) then
            [ [ section ] ]
          else if section == [ ] || !isList (val (head (val section))) then
            [ section ]
          else
            section;

        phases = mapAttrs (_: concatStringsSep "\n")
          (foldl mergeAttrsConcatenateValues {
            buildPhase = [ ];
            checkPhase = [ ];
          } (map (command: {
            ${
              if hasOpt "with-test" command then "checkPhase" else "buildPhase"
            } = [ (renderCommand command) ];
          }) (evalSection pkgdef.build or [ ])));

        evalSection = section:
          filter (x: !isNull (val x))
          (map evalValueKeepOptions (normalize section));

        passthru = {

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
            depends = packageDepends;

            bin = "${pkg}/bin";
            sbin = "${pkg}/bin";
            lib = "${pkg}/lib/ocaml/${deps.ocaml.version}/site-lib/${name}";
            man = "${pkg}/share/man";
            doc = "${pkg}/share/doc";
            share = "${pkg}/share";
            etc = "${pkg}/etc";
          };
          pkgdef = pkgdef;
        };
        archive = pkgdef.url.src or pkgdef.url.archive;
        src = if pkgdef ? url then
        # Default unpacker doesn't support .zip
          if hashes == [ ] || hasSuffix ".zip" archive then
            builtins.fetchTarball archive
          else
            deps.fetchurl ({ url = archive; } // head hashes)
        else
          pkgs.emptyDirectory;

        fake-opam = pkgs.writeShellScriptBin "opam" ''echo "$out"'';

        pkg = deps.stdenv.mkDerivation {
          pname = name;
          inherit version;
          inherit (sortedDeps) buildInputs checkInputs;

          propagatedBuildInputs = sortedDeps.buildInputs;

          inherit passthru;
          doCheck = false;

          inherit src;

          nativeBuildInputs = sortedDeps.nativeBuildInputs
            ++ [ deps.ocamlfind ] # Used to add relevant packages to OCAMLPATH
            ++ optional (deps ? dune) fake-opam # Dune uses `opam var prefix` to get the prefix, which we want set to $out
            ++ optional (!pkgdef ? install) deps.opam-installer;

          configurePhase = ''
            runHook preConfigure
            ${optionalString (pkgdef ? files) "cp -R ${pkgdef.files}/* ."}
            patchShebangs .
            export OCAMLTOP_INCLUDE_PATH="$OCAMLPATH"
            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild
            ${phases.buildPhase}
            runHook postBuild
          '';
          checkPhase = ''
            runHook preCheck
            ${phases.checkPhase}
            runHook postCheck
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $OCAMLFIND_DESTDIR
            ${concatMapStringsSep "\n" renderCommand
            (evalSection pkgdef.install or [ ])}
            if [[ -e ${name}.install ]]; then
              opam-installer ${name}.install --prefix=$out --libdir=$OCAMLFIND_DESTDIR
            fi
            runHook postInstall
          '';
        };
      in pkg;

  };
}
