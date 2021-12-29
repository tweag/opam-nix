# Pkgset = { ${name} = { ${version} = Pkgdef; ... } ... }
# Pkgdef = { name = String; version = String; depends = [OpamVar]; build = ?[[String]]; install = ?[[String]]; ... }

inputs: bootstrapPackages:
let
  inherit (builtins)
    readDir mapAttrs concatStringsSep concatMap all isString isList elem
    attrValues filter attrNames head elemAt splitVersion foldl' fromJSON
    listToAttrs readFile getAttr toFile match isAttrs pathExists toJSON deepSeq
    length;
  inherit (bootstrapPackages) lib;
  inherit (lib)
    versionAtLeast splitString tail mapAttrs' nameValuePair zipAttrsWith collect
    filterAttrs unique subtractLists concatMapStringsSep concatLists reverseList
    fileContents pipe makeScope optionalAttrs filterAttrsRecursive hasSuffix
    converge mapAttrsRecursive hasAttr composeManyExtensions removeSuffix
    optionalString last init recursiveUpdate foldl getAttrs optional;

  readDirRecursive = dir:
    mapAttrs (name: type:
      if type == "directory" then readDirRecursive "${dir}/${name}" else type)
    (readDir dir);

  # [Pkgset] -> Pkgset
  mergePackageSets = zipAttrsWith (_: foldl' (a: b: a // b) { });

  #bootstrapPackagesStub = import ./bootstrapPackages.nix { };

  #bootstrapPackageNames = attrNames bootstrapPackagesStub;
in rec {
  # filterRelevant (traverseOPAMRepository ../../opam-repository) "opam-ed"
  opam2json-overlay = self: super: { opam2json = self.ocamlPackages.callPackage (import ./opam2json.nix inputs.opam2json) {}; };

  inherit (bootstrapPackages.extend (opam2json-overlay)) opam2json;

  # Path -> {...}
  fromOPAM = opamFile:
    let
      json = bootstrapPackages.runCommandNoCC "opam.json" {
        preferLocalBuild = true;
        allowSubstitutes = false;
      } "${opam2json}/bin/opam2json ${opamFile} > $out";
    in fromJSON (readFile json);

  fromOPAM' = opamText: fromOPAM (toFile "opam" opamText);

  # Pkgdef -> Derivation
  builder = import ./builder.nix bootstrapPackages.lib;

  # Path -> Derivation
  opam2nix = { opamFile, name ? null, version ? null }:
    builder (fromOPAM opamFile // { inherit name version; });

  splitNameVer = nameVer:
    let nv = nameVerToValuePair nameVer;
    in {
      inherit (nv) name;
      version = nv.value;
    };

  nameVerToValuePair = nameVer:
    let split = splitString "." nameVer;
    in nameValuePair (head split) (concatStringsSep "." (tail split));

  ops = {
    eq = "=";
    gt = ">";
    lt = "<";
    geq = ">=";
    leq = "<=";
    neq = "!=";
  };

  global-variables = import ./global-variables.nix;

  opamListToQuery = list: listToAttrs (map nameVerToValuePair list);

  opamList = repo: env: packages:
    let
      pkgRequest = name: version:
        if isNull version then name else "${name}.${version}";

      toString' = x: if isString x then x else toJSON x;

      environment = concatStringsSep ";"
        (attrValues (mapAttrs (name: value: "${name}=${toString' value}") env));

      query = concatStringsSep "," (attrValues (mapAttrs pkgRequest packages));

      resolve-drv = bootstrapPackages.runCommand "resolve" {
        nativeBuildInputs = [ bootstrapPackages.opam ];
        OPAMNO = "true";
        OPAMCLI = "2.0";
      } ''
        export OPAMROOT=$NIX_BUILD_TOP/opam

        cd ${repo}

        opam admin list --resolve=${query} --short --depopts --columns=package ${
          optionalString (!isNull env) "--environment='${environment}'"
        } | tee $out
      '';
      solution = fileContents resolve-drv;

      lines = s: splitString "\n" s;

    in lines solution;

  listToAttrsBy = by: list: listToAttrs (map (x: nameValuePair x.${by} x) list);

  contentAddressedIFD = dir:
    deepSeq (readDir dir) (/. + builtins.unsafeDiscardStringContext dir);

  makeOpamRepo = dir:
    let
      files = readDirRecursive dir;
      opamFiles = filterAttrsRecursive
        (name: value: isAttrs value || hasSuffix "opam" name) files;
      opamFilesOnly =
        converge (filterAttrsRecursive (_: v: v != { })) opamFiles;
      packages = concatLists (collect isList (mapAttrsRecursive
        (path': _: [rec {
          fileName = last path';
          dirName = splitNameVer (last (init path'));
          parsedOPAM = fromOPAM opamFile;
          name = parsedOPAM.name or (if hasSuffix ".opam" fileName then
            removeSuffix ".opam" fileName
          else
            dirName.name);

          version = parsedOPAM.version or (if dirName.version != "" then
            dirName.version
          else
            "local");
          source = dir + ("/" + concatStringsSep "/" (init path'));
          opamFile = "${dir + ("/" + (concatStringsSep "/" path'))}";
        }]) opamFilesOnly));
      repo-description = {
        name = "repo";
        path = toFile "repo" ''opam-version: "2.0"'';
      };
      opamFileLinks = map ({ name, version, opamFile, ... }: {
        name = "packages/${name}/${name}.${version}/opam";
        path = opamFile;
      }) packages;
      sourceMap = foldl (acc: x:
        recursiveUpdate acc {
          ${x.name} = { ${x.version} = contentAddressedIFD x.source; };
        }) { } packages;
      repo = bootstrapPackages.linkFarm "opam-repo"
        ([ repo-description ] ++ opamFileLinks);
    in repo // { passthru.sourceMap = sourceMap; };

  queryToDefs = repos: packages:
    let
      findPackage = name: version:
        let
          pkgDir = repo: repo + "/packages/${name}/${name}.${version}";
          filesPath = contentAddressedIFD (pkgDir repo + "/files");
          repo = head (filter (repo: pathExists (pkgDir repo)) repos);
          isLocal = repo ? passthru.sourceMap;
        in {
          opamFile = pkgDir repo + "/opam";
          inherit name version isLocal repo;
        } // optionalAttrs (pathExists (pkgDir repo + "/files")) {
          files = filesPath;
        } // optionalAttrs isLocal {
          src = bootstrapPackages.runCommand "source-copy" { }
            "cp --no-preserve=all -R ${
              repo.passthru.sourceMap.${name}.${version}
            }/ $out";
        };

      packageFiles = mapAttrs findPackage packages;
    in mapAttrs
    (_: { opamFile, name, version, ... }@args: args // (fromOPAM opamFile))
    packageFiles;

  callPackageWith = autoArgs: fn: args:
    let
      f = if lib.isAttrs fn then
        fn
      else if lib.isFunction fn then
        fn
      else
        import fn;
      auto =
        builtins.intersectAttrs (f.__functionArgs or (builtins.functionArgs f))
        autoArgs;
    in lib.makeOverridable f (auto // args);

  defsToScope = pkgs: defs:
    makeScope callPackageWith (self:
      (mapAttrs (name: pkg: self.callPackage (builder pkg) { }) defs) // {
        nixpkgs = pkgs.extend opam2json-overlay;
      });

  defaultOverlay = import ./overlays/ocaml.nix;
  staticOverlay = import ./overlays/ocaml-static.nix;

  applyOverlays = overlays: scope:
    scope.overrideScope' (composeManyExtensions overlays);

  joinRepos = repos:
    if length repos == 1 then
      head repos
    else
      bootstrapPackages.symlinkJoin {
        name = "opam-repo";
        paths = repos;
      };

  queryToScope = { repos, pkgs ? bootstrapPackages, overlays ?
      [ defaultOverlay ]
      ++ optional pkgs.stdenv.hostPlatform.isStatic staticOverlay, env ? null }:
    query:
    pipe query [
      (opamList (joinRepos repos) env)
      (opamListToQuery)
      (queryToDefs repos)
      (defsToScope pkgs)
      (applyOverlays overlays)
    ];

  opamImport = { repos, pkgs }:
    export:
    let
      installedList = (fromOPAM export).installed;
      set = pipe installedList [
        opamListToQuery
        (queryToDefs repos)
        (defsToScope repos pkgs)
      ];
      installedPackageNames = map (x: (splitNameVer x).name) installedList;
      combined = pkgs.symlinkJoin {
        name = "opam-switch";
        paths = attrValues (getAttrs installedPackageNames set);
      };
    in combined;
}
