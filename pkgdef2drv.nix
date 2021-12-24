pkgs:
with builtins;
with pkgs.lib;
{ name, version, ... }@pkgdef: rec {
  alwaysNative = import ./always-native.nix;

  globalVariables = import ./global-variables.nix pkgs;

  val = x: x.val or x;

  hasOpt' = opt: dep: elem opt dep.options or [ ];

  hasOpt = opt: hasOpt' { id = opt; };

  fallbackPackageVars = name: {
    inherit name;
    installed = false;
    enable = "disable";
    version = "";
  };

  filterOutEmpty = converge (filterAttrsRecursive (_: v: v != { }));

  # Get _all_ dependencies mentioned in the opam file

  collectAllDeps = v:
    if isString v then
      [ v ]
    else if v ? val && isString v.val then
      [ v.val ]
    else if v ? val && isList v.val then
      concatMap collectAllDeps v.val
    else if isList v then
      concatMap collectAllDeps v
    else
      throw "unexpected dependency: ${toJSON v}";

  allDepends = collectAllDeps pkgdef.depends or [ ];
  allDepopts = collectAllDeps pkgdef.depopts or [ ];

  genArgs = deps: optional:
    listToAttrs (map (name: nameValuePair name optional) deps);

  __functionArgs = {
    extraDeps = true;
    extraVars = true;
    native = false;

    stdenv = false;
    fetchurl = true;
    opam-installer = true;
    ocamlfind = false;
    ocaml = true;
  } // genArgs allDepends false // genArgs allDepopts true;

  __functor = self: deps:
    with self;
    let
      compareVersions' = op: a: b:
        let comp = compareVersions a (evalValue b);
        in if op == "eq" then
          comp == 0
        else if op == "lt" then
          comp == -1
        else if op == "gt" then
          comp == 1
        else if op == "leq" then
          comp < 1
        else if op == "geq" then
          comp > -1
        else
          true;

      checkVersionConstraint = pkg: version:
        (!version ? op) || deps ? ${pkg}
        && compareVersions' version.op deps.${pkg}.version (head version.val);

      collectAcceptableVerisions = v:
        let
          a = elemAt v.val 0;
          b = elemAt v.val 1;
          a' = collectAcceptableVerisions a;
          b' = collectAcceptableVerisions b;
          framaTrace = if name == "frama-c" then traceValSeq else id;
        in if v ? op then
          if v.op == "or" then
            if a' != [ ] then a' else if b' != [ ] then b' else [ ]
          else if v.op == "and" then
            if !isNull a' && !isNull b' then a' ++ b' else [ ]
          else
            throw "Not a logop: ${v.op}"
        else if v ? options then
          if all (checkVersionConstraint v.val) v.options then [ v ] else [ ]
        else if isString v then
          if deps ? ${v} then [ v ] else [ ]
        else if isList v then
          concatMap collectAcceptableVerisions v
        else
          v;

      relevantDepends = collectAcceptableVerisions
        ((pkgdef.depends or [ ]) ++ pkgdef.depopts or [ ]);

      # Either String StringWithOption -> String
      depType = dep:
        if hasOpt "with-test" dep then
          "checkInputs"
        else if builtins.elem (val dep) alwaysNative || hasOpt "build" dep then
          "nativeBuildInputs"
        else
          "buildInputs";

      sortedDepNames = foldl mergeAttrsConcatenateValues {
        buildInputs = [ ];
        checkInputs = [ ];
        nativeBuildInputs = [ ];
      } (map (dep: { ${depType dep} = [ (val dep) ]; }) relevantDepends);

      sortedDeps = mapAttrs (_:
        map
        (x: deps.${x} or (builtins.trace "${name}: missing dep: ${x}" null)))
        sortedDepNames;

      packageDepends = removeAttrs deps [ "extraDeps" "extraVars" "stdenv" ];

      stubOutputs = {
        prefix = "$out";
        bin = "$out/bin";
        sbin = "$out/bin";
        lib = "$OCAMLFIND_DESTDIR";
        man = "$out/share/man";
        doc = "$out/share/doc";
        share = "$out/share";
        etc = "$out/etc";
        build = "$NIX_BUILD_TOP/$sourceRoot";
      };

      vars = globalVariables // {
        with-test = false;
        with-doc = false;
        build = true;
      } // (mapAttrs
        (name: pkg: pkg.passthru.vars or (fallbackPackageVars name))
        packageDepends) // (deps.extraVars or { }) // rec {
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

      # FIXME: There are more operators
      evalOp = op: vals:
        let
          fst = elemAt vals 0;
          snd = elemAt vals 1;
          fst' = toString fst;
          snd' = toString snd;
          compareVersions' = if fst' == "" || snd' == "" then
            null
          else
            compareVersions fst' snd';
        in if op == "eq" then
          fst' == snd'
        else if op == "gt" then
          compareVersions' == 1
        else if op == "lt" then
          compareVersions' == -1
        else if op == "geq" then
          compareVersions' == 1 || compareVersions == 0
        else if op == "leq" then
          compareVersions' == -1 || compareVersions == 0
        else if op == "neq" then
          fst' != snd'
        else if op == "not" then
          !fst
        else if op == "and" then
          fst && snd
        else if op == "or" then
          fst || snd
        else
          throw "Operation ${op} not implemented";

      evalValue = val:
        if val ? id then
          getVar (splitString ":" val.id)
        else if val ? op then
          evalOp val.op
          (map (x: if isList x then head (map evalValue x) else evalValue x)
            val.val)
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
        in if isNull e then
          ""
        else
          ''
            "${e}"''; # We use `"` instead of `'` here because we want to interpret variables like $out

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
              result = result
                + (if i then toString' (evalValue { id = piece; }) else piece);
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
          ${if hasOpt "with-test" command then "checkPhase" else "buildPhase"} =
            [ (renderCommand command) ];
        }) (evalSection pkgdef.build or [ ])));

      evalSection = section:
        filter (x: !isNull (val x))
        (map evalValueKeepOptions (normalize section));

      nativePackages = import ./native-package-map.nix deps.native;

      extInputNames = concatLists (filter (x: !isNull x)
        (map evalValue (normalize pkgdef.depexts or [ ])));

      extInputs =
        map (x: if isString x then nativePackages.${x} else null) extInputNames;

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
          lib = "${pkg}/lib/ocaml/${deps.ocaml.version}/site-lib";
          man = "${pkg}/share/man";
          doc = "${pkg}/share/doc";
          share = "${pkg}/share";
          etc = "${pkg}/etc";

          __toString = self: self.version;
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
        pkgdef.src or pkgs.emptyDirectory;

      fake-opam = pkgs.writeShellScriptBin "opam" ''echo "$out"'';

      isOpamNixPackage = pkg: pkg ? passthru.pkgdef;

      propagatedExternalBuildInputs = concatMap (dep:
        optionals (isOpamNixPackage dep)
        (dep.buildInputs or [ ] ++ dep.propagatedBuildInputs or [ ]))
        (attrValues deps);

      unique' = foldl' (acc: e:
        if elem (toString e) (map toString acc) then acc else acc ++ [ e ]) [ ];

      uniqueBuildInputs = unique'
        (sortedDeps.buildInputs ++ extInputs ++ propagatedExternalBuildInputs);

      pkg = deps.stdenv.mkDerivation {
        pname = name;
        inherit version;
        inherit (sortedDeps) checkInputs;

        # Ocaml packages may expect that all their transitive dependencies are present :(
        # We call unique here to prevent bash failing with too many arguments
        buildInputs = uniqueBuildInputs;

        inherit passthru;
        doCheck = false;

        inherit src;

        nativeBuildInputs = sortedDeps.nativeBuildInputs ++ [
          deps.ocamlfind
          deps.opam-installer
          deps.ocaml
        ] # Used to add relevant packages to OCAMLPATH
          ++ optional (deps ? dune) fake-opam;
        # Dune uses `opam var prefix` to get the prefix, which we want set to $out

        configurePhase = ''
          runHook preConfigure
          ${optionalString (pkgdef ? files) "cp -R ${pkgdef.files}/* ."}
          if [[ -z $dontPatchShebangsEarly ]]; then patchShebangs .; fi
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
          # Some installers expect the installation directories to be present
          mkdir -p $OCAMLFIND_DESTDIR $out/bin
          ${concatMapStringsSep "\n" renderCommand
          (evalSection pkgdef.install or [ ])}
          if [[ -e ${name}.install ]]; then
            opam-installer ${name}.install --prefix=$out --libdir=$OCAMLFIND_DESTDIR
          fi
          if [[ -e $out/lib/${name}/META ]] && [[ ! -e $OCAMLFIND_DESTDIR/${name} ]]; then
            mv $out/lib/${name} $OCAMLFIND_DESTDIR
          fi
          if [[ -z "$(ls $out/bin)" ]]; then
            rm -d "$out/bin"
          fi
          if [[ -z "$(ls $OCAMLFIND_DESTDIR)" ]]; then
            rm -rf $out/lib/ocaml
            if [[ -z "$(ls $out/lib)" ]]; then
              rm -rf $out/lib
            fi
          fi
          if [[ ! -d $OCAMLFIND_DESTDIR/${name} ]] && [[ -e $OCAMLFIND_DESTDIR/META ]]; then
            mv $OCAMLFIND_DESTDIR $NIX_BUILD_TOP/destdir
            mkdir -p $OCAMLFIND_DESTDIR
            mv $NIX_BUILD_TOP/destdir $OCAMLFIND_DESTDIR/${name}
          fi
          runHook postInstall
        '';
      };
    in pkg;

}
