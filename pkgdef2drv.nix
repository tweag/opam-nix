lib:

let
  inherit (builtins)
    elem isString isList isBool isInt concatMap toJSON listToAttrs
    compareVersions head all elemAt length match filter split concatStringsSep
    concatLists attrValues foldl' trace;
  inherit (lib)
    converge filterAttrsRecursive nameValuePair splitString optional hasSuffix
    optionalString concatMapStringsSep foldl mergeAttrsConcatenateValues
    mapAttrs hasAttrByPath getAttrFromPath tail optionalAttrs optionals
    recursiveUpdate escapeShellArg;

in { name, version, ... }@pkgdef: rec {
  alwaysNative = import ./always-native.nix;

  globalVariables = import ./global-variables.nix;

  val = x: x.val or x;

  hasOpt' = opt: dep: elem opt dep.options or [ ];

  hasOpt = opt: hasOpt' { id = opt; };

  fallbackPackageVars = name: {
    inherit name;
    installed = false;
    enable = "disable";
    version = "";
  };

  inherit (import ./lib.nix lib) md5sri propagateInputs;

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
    nixpkgs = false;
    buildPackages = false;

    stdenv = false;
    fetchurl = true;
    opam-installer = true;
    ocamlfind = false;
    ocaml = true;
  } // genArgs allDepends false // genArgs allDepopts true;

  __functor = self: deps:
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
        (!version ? op) || (deps ? ${pkg} && !isNull deps.${pkg}
          && compareVersions' version.op deps.${pkg}.version
          (head version.val));

      versionResolutionVars = {
        with-test = false;
        with-doc = false;
        build = true;
      };

      collectAcceptableVerisions = v:
        let
          a = elemAt v.val 0;
          b = elemAt v.val 1;
          a' = collectAcceptableVerisions a;
          b' = collectAcceptableVerisions b;
        in if v ? op then
          if v.op == "or" then
            if a' != [ ] then a' else if b' != [ ] then b' else [ ]
          else if v.op == "and" then
            if a' != [ ] && b' != [ ] then a' ++ b' else [ ]
          else
            throw "Not a logop: ${v.op}"
        else if v ? options then
          if all (opt:
            checkVersionConstraint v.val opt
            && (versionResolutionVars.${opt.id or "_"} or true)) v.options then
            [ v ]
          else
            [ ]
        else if isString v then
          if deps ? ${v} && !isNull deps.${v} then [ v ] else [ ]
        else if isList v then
          concatMap collectAcceptableVerisions v
        else
          v;

      relevantDepends = collectAcceptableVerisions
        ((pkgdef.depends or [ ]) ++ pkgdef.depopts or [ ]);

      # Either String StringWithOption -> String
      # depType = dep:
      #   if hasOpt "with-test" dep then
      #     "checkInputs"
      #   else if elem (val dep) alwaysNative || hasOpt "build" dep then
      #     "nativeBuildInputs"
      #   else
      #     "buildInputs";

      # sortedDepNames = foldl mergeAttrsConcatenateValues {
      #   buildInputs = [ ];
      #   checkInputs = [ ];
      #   nativeBuildInputs = [ ];
      # } (map (dep: { ${depType dep} = [ (val dep) ]; }) relevantDepends);

      # sortedDeps = mapAttrs
      #   (_: map (x: deps.${x} or (trace "${name}: missing dep: ${x}" null)))
      #   sortedDepNames;

      ocamlInputs = map (x: deps.${val x} or (trace "${name}: missing dep: ${x}" null)) relevantDepends;

      packageDepends = removeAttrs deps [ "extraDeps" "extraVars" "stdenv" ];

      stubOutputs = rec {
        prefix = placeholder "out";
        bin = "${prefix}/bin";
        sbin = "${prefix}/bin";
        lib = "${prefix}/lib/ocaml/${deps.ocaml.version}/site-lib";
        man = "${prefix}/share/man";
        doc = "${prefix}/share/doc";
        share = "${prefix}/share";
        etc = "${prefix}/etc";
        build = ".";
      };

      vars = globalVariables // {
        with-test = false;
        with-doc = false;
        # build = true;
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
          if isNull fst then null else !fst
        else if op == "and" then
          if isNull fst || isNull snd then null else fst && snd
        else if op == "or" then
          if isNull fst then if isNull snd then null else snd else fst || snd
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

      tryHash = method: c:
        let m = match "${method}=(.*)" c;
        in if isNull m then [ ] else [{ ${method} = head m; }];

      # md5 is special in two ways:
      # nixpkgs only accepts it as an SRI,
      # and checksums without an explicit algo are assumed to be md5 in opam
      trymd5 = c:
        let
          m = match "md5=(.*)" c;
          m' = match "([0-9a-f]{32})" c;
          success = md5: [{ hash = md5sri (head md5); }];
        in if !isNull m then
          success m
        else if !isNull m' then
          success m'
        else
          [ ];

      tryHashes = x: tryHash "sha512" x ++ tryHash "sha256" x ++ trymd5 x;

      hashes = foldl recursiveUpdate { } (if pkgdef.url ? checksum then
        if isList pkgdef.url.checksum then
          concatMap tryHashes pkgdef.url.checksum
        else
          tryHashes pkgdef.url.checksum
      else
        [ ]);

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

      externalPackages =
        import ./external-package-map.nix deps.nixpkgs deps.buildPackages;

      extInputNames = concatLists (filter (x: !isNull x)
        (map evalValue (normalize pkgdef.depexts or [ ])));

      extInputs = map (x: if isString x then externalPackages.${x} else null)
        extInputNames;

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
        transitiveInputs = propagateInputs
          (ocamlInputs ++ extInputs);
      };
      archive = pkgdef.url.src or pkgdef.url.archive or "";
      src = if pkgdef ? url then
      # Default unpacker doesn't support .zip
        if hashes == { } then
          builtins.fetchTarball archive
        else
          deps.nixpkgs.fetchurl ({ url = archive; } // hashes)
      else
        pkgdef.src or deps.nixpkgs.emptyDirectory;

      fake-opam = deps.nixpkgs.writeShellScriptBin "opam" ''echo "$out"'';

      messages = filter isString
        (map evalValue (pkgdef.messages or [ ] ++ pkgdef.post-messages or [ ]));

      traceAllMessages = val:
        foldl' (acc: x: trace "${name}: ${x}" acc) val messages;

      pkg = deps.nixpkgs.stdenv.mkDerivation {
        pname = traceAllMessages name;
        inherit version;

        # Ocaml packages may expect that all their transitive dependencies are present :(
        # We call unique here to prevent bash failing with too many arguments
        buildInputs = extInputs ++ ocamlInputs;

        inherit passthru;
        doCheck = false;

        inherit src;

        nativeBuildInputs = extInputs ++ ocamlInputs ++ [
          deps.ocamlfind # Used to add relevant packages to OCAMLPATH
          deps.opam-installer
          deps.ocaml
        ] ++ optional (deps ? dune) fake-opam
          ++ optional (hasSuffix ".zip" archive) deps.nixpkgs.unzip;
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
          mkdir -p "$out/nix-support"
          printf ${
            escapeShellArg (toString passthru.transitiveInputs)
          } > "$out/nix-support/propagated-build-inputs"
          runHook postInstall
        '';
      };
    in pkg;

}
