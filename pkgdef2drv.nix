pkgs:
with builtins;
with pkgs.lib; rec {
  alwaysNative = import ./package-maps/always-native.nix;

  globalVariables = import ./global-variables.nix pkgs;

  pkgdeftodrv = { name, version, depends, build, ... }@pkgdef: rec {
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
      else if builtins.elem (val dep) alwaysNative
      || hasOpt "build" dep then
        "nativeBuildInputs"
      else
        "buildInputs";

    # "Sort" the depends into three categories
    # { buildInputs = [ String ]; checkInputs = [ String ]; nativeBuildInputs = [ String ] }
    sortedDepNames = foldl mergeAttrsConcatenateValues {
      buildInputs = [ ];
      checkInputs = [ ];
      nativeBuildInputs = [ ];
    } (map (dep: { ${depType dep} = [ (val dep) ]; }) depends);


    __functionArgs = trace "deps for ${name}" {
      extraDeps = true;
      extraVars = true;

      stdenv = false;
      fetchurl = true;
      opam-installer = true;
    } // deps-optional;

    __functor = self: deps:
      with self;
      let
        sortedDeps = mapAttrs (_: map (flip getAttr deps)) sortedDepNames;

        packageDepends = removeAttrs deps [ "extraDeps" "extraVars" "stdenv" ];

        stubOutputs = {
          bin = "$out/bin";
          sbin = "$out/bin";
          lib = "$out/lib";
          man = "$out/share/man";
          doc = "$out/share/doc";
          share = "$out/share";
          etc = "$out/etc";
        };

        vars = globalVariables // (mapAttrs (_: pkg: pkg.passthru.vars) packageDepends) // (deps.extraVars or { }) // rec {
            _ = passthru.vars // stubOutputs;
            ${name} = _;
          } // passthru.vars // stubOutputs;

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

        getVar = path:
          if hasAttrByPath path vars then getAttrFromPath path vars else null;

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
            val;

        evalCommandEntry = entry:
          let e = evalValue entry;
          in if isNull e then "" else e;

        renderCommand = concatMapStringsSep " " evalCommandEntry;

        trySha256 = c:
          let m = match "sha256=(.*)" c;
          in if isNull m then [ ] else [{ sha256 = head m; }];
        trySha512 = c:
          let m = match "sha512=(.*)" c;
          in if isNull m then [ ] else [{ sha512 = head m; }];

        hashes = concatMap (x: trySha512 x ++ trySha256 x) pkgdef.url.checksum;

        # FIXME do this for every section
        normalize = section: if !isList (val section) then
          [ [ section ] ]
        else if !isList (val (head (val section))) then
          [ section ]
        else
          section;

        phases = mapAttrs (_: concatStringsSep "\n") (foldl mergeAttrsConcatenateValues {
          buildPhase = [ ];
          checkPhase = [ ];
        } (map (command: {
          ${if hasOpt "with-test" command then "checkPhase" else "buildPhase"} = [ (renderCommand (traceValSeq command)) ];
        }) (evalSection build)));

        evalSection = section: filter (x: ! isNull x) (map evalValue (normalize section));

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
            lib = "${pkg}/lib";
            man = "${pkg}/share/man";
            doc = "${pkg}/share/doc";
            share = "${pkg}/share";
            etc = "${pkg}/etc";
          };
          pkgdef = pkgdef;
        };

        pkg = deps.stdenv.mkDerivation {
          pname = name;
          inherit version;

          src = if hashes == [ ] then
            builtins.fetchTarball pkgdef.url.src
          else
            deps.fetchurl ({ url = pkgdef.url.src; } // head hashes);

          inherit (sortedDeps) buildInputs checkInputs;

          doCheck = false;

          nativeBuildInputs = sortedDeps.nativeBuildInputs
            ++ optional (! pkgdef ? install) deps.opam-installer;

          configurePhase = ":";

          inherit (phases) buildPhase checkPhase;

          installPhase = if pkgdef ? install then
            concatMapStringsSep "\n" renderCommand (evalSection pkgdef.install)
          else ''
            opam-installer *.install --prefix=$out
          '';

          inherit passthru;
        };
      in pkg;

  };
}
