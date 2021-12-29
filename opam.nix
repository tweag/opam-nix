# Pkgset = { ${name} = { ${version} = Pkgdef; ... } ... }
# Pkgdef = { name = String; version = String; depends = [OpamVar]; build = ?[[String]]; install = ?[[String]]; ... }

args:
let
  inherit (builtins)
    readDir mapAttrs concatStringsSep isString isList attrValues filter head
    foldl' fromJSON listToAttrs readFile toFile isAttrs pathExists toJSON
    deepSeq length sort concatMap attrNames;
  bootstrapPackages = args.pkgs;
  opamRepository = args.opam-repository;
  inherit (bootstrapPackages) lib;
  inherit (lib)
    splitString tail nameValuePair zipAttrsWith collect concatLists
    filterAttrsRecursive fileContents pipe makeScope optionalAttrs hasSuffix
    converge mapAttrsRecursive composeManyExtensions removeSuffix optionalString
    last init recursiveUpdate foldl optional;

  inherit (import ./opam-evaluator.nix lib) compareVersions';

  readDirRecursive = dir:
    mapAttrs (name: type:
      if type == "directory" then readDirRecursive "${dir}/${name}" else type)
    (readDir dir);

  # [Pkgset] -> Pkgset
  mergePackageSets = zipAttrsWith (_: foldl' (a: b: a // b) { });

  inherit (bootstrapPackages)
    runCommandNoCC linkFarm symlinkJoin opam2json opam;
  splitNameVer = nameVer:
    let nv = nameVerToValuePair nameVer;
    in {
      inherit (nv) name;
      version = nv.value;
    };

  nameVerToValuePair = nameVer:
    let split = splitString "." nameVer;
    in nameValuePair (head split) (concatStringsSep "." (tail split));

  # Pkgdef -> Derivation
  builder = import ./builder.nix bootstrapPackages.lib;

  contentAddressedIFD = dir:
    deepSeq (readDir dir) (/. + builtins.unsafeDiscardStringContext dir);

  global-variables = import ./global-variables.nix;

  mergeSortVersions = zipAttrsWith (_: sort (compareVersions' "lt"));
in rec {

  # Path -> {...}
  importOpam = opamFile:
    let
      json = runCommandNoCC "opam.json" {
        preferLocalBuild = true;
        allowSubstitutes = false;
      } "${opam2json}/bin/opam2json ${opamFile} > $out";
    in fromJSON (readFile json);

  fromOpam = opamText: importOpam (toFile "opam" opamText);

  # Path -> Derivation
  opam2nix =
    { src, opamFile ? src + "/${name}.opam", name ? null, version ? null }:
    builder (importOpam opamFile // { inherit src name version; });

  listRepo = repo:
    mergeSortVersions (map (p: listToAttrs [ (nameVerToValuePair p) ])
      (concatMap attrNames
        (attrValues (readDirRecursive (repo + "/packages")))));

  opamListToQuery = list: listToAttrs (map nameVerToValuePair list);

  opamList = repo: env: packages:
    let
      pkgRequest = name: version:
        if isNull version then name else "${name}.${version}";

      toString' = x: if isString x then x else toJSON x;

      environment = concatStringsSep ";"
        (attrValues (mapAttrs (name: value: "${name}=${toString' value}") env));

      query = concatStringsSep "," (attrValues (mapAttrs pkgRequest packages));

      resolve-drv = runCommandNoCC "resolve" {
        nativeBuildInputs = [ opam ];
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
          parsedOPAM = importOpam opamFile;
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
      repo = linkFarm "opam-repo" ([ repo-description ] ++ opamFileLinks);
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
          src = runCommandNoCC "source-copy" { } "cp --no-preserve=all -R ${
              repo.passthru.sourceMap.${name}.${version}
            }/ $out";
        };

      packageFiles = mapAttrs findPackage packages;
    in mapAttrs
    (_: { opamFile, name, version, ... }@args: args // (importOpam opamFile))
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
        nixpkgs = pkgs.extend (_: _: { inherit opam2json; });
      });

  defaultOverlay = import ./overlays/ocaml.nix;
  staticOverlay = import ./overlays/ocaml-static.nix;

  applyOverlays = overlays: scope:
    scope.overrideScope' (composeManyExtensions overlays);

  joinRepos = repos:
    if length repos == 1 then
      head repos
    else
      symlinkJoin {
        name = "opam-repo";
        paths = repos;
      };

  queryToScope = { repos ? [ opamRepository ], pkgs ? bootstrapPackages
    , overlays ? [ defaultOverlay ]
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
    let installedList = (importOpam export).installed;
    in pipe installedList [
      opamListToQuery
      (queryToDefs repos)
      (defsToScope repos pkgs)
    ];
}
