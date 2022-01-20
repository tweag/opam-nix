# Pkgset = { ${name} = { ${version} = Pkgdef; ... } ... }
# Pkgdef = { name = String; version = String; depends = [OpamVar]; build = ?[[String]]; install = ?[[String]]; ... }

args:
let
  inherit (builtins)
    readDir mapAttrs concatStringsSep isString isList attrValues filter head
    foldl' fromJSON listToAttrs readFile toFile isAttrs pathExists toJSON
    deepSeq length sort concatMap attrNames;
  bootstrapPackages = args.pkgs;
  inherit (bootstrapPackages) lib;
  inherit (lib)
    splitString tail nameValuePair zipAttrsWith collect concatLists
    filterAttrsRecursive fileContents pipe makeScope optionalAttrs hasSuffix
    converge mapAttrsRecursive composeManyExtensions removeSuffix optionalString
    last init recursiveUpdate foldl optional optionals importJSON;

  inherit (import ./opam-evaluator.nix lib) compareVersions';

  readDirRecursive = dir:
    mapAttrs (name: type:
      if type == "directory" then readDirRecursive "${dir}/${name}" else type)
    (readDir dir);

  # [Pkgset] -> Pkgset
  mergePackageSets = zipAttrsWith (_: foldl' (a: b: a // b) { });

  inherit (bootstrapPackages)
    runCommandNoCC linkFarm symlinkJoin opam2json opam;

  # Pkgdef -> Derivation
  builder = import ./builder.nix bootstrapPackages.lib;

  contentAddressedIFD = dir:
    deepSeq (readDir dir) (/. + builtins.unsafeDiscardStringContext dir);

  global-variables =
    import ./global-variables.nix bootstrapPackages.stdenv.hostPlatform;

  defaultEnv = { inherit (global-variables) os os-family os-distribution; };

  mergeSortVersions = zipAttrsWith (_: sort (compareVersions' "lt"));

  readFileContents = { files ? bootstrapPackages.emptyDirectory, ... }@def:
    (builtins.removeAttrs def [ "files" ]) // {
      files-contents =
        mapAttrs (name: _: readFile (files + "/${name}")) (readDir files);
    };

  writeFileContents = { name ? "opam", files-contents ? { }, ... }@def:
    (builtins.removeAttrs def [ "files-contents" ])
    // optionalAttrs (files-contents != { }) {
      files = symlinkJoin {
        name = "${name}-files";
        paths =
          (attrValues (mapAttrs bootstrapPackages.writeTextDir files-contents));
      };
    };

  eraseStoreReferences = def:
    builtins.removeAttrs def [ "repo" "opamFile" "src" ];

  # Note: there can only be one version of the package present in packagedefs we're working on
  injectSources = sourceMap: def:
    if sourceMap ? ${def.name} then
      def // { src = sourceMap.${def.name}; }
    else
      def;

  isImpure = builtins ? currentSystem;

  namePathPair = name: path: { inherit name path; };
in rec {

  splitNameVer = nameVer:
    let nv = nameVerToValuePair nameVer;
    in {
      inherit (nv) name;
      version = nv.value;
    };

  nameVerToValuePair = nameVer:
    let split = splitString "." nameVer;
    in nameValuePair (head split) (concatStringsSep "." (tail split));

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
    builder ({ inherit src name version; } // importOpam opamFile);

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
        nativeBuildInputs = [ opam bootstrapPackages.ocaml ];
        OPAMCLI = "2.0";
      } ''
        export OPAMROOT=$NIX_BUILD_TOP/opam

        cd ${repo}
        opam admin list --resolve=${query} --short --depopts --dev --columns=package ${
          optionalString (!isNull env) "--environment '${environment}'"
        } | tee $out
      '';
      solution = fileContents resolve-drv;

      lines = s: splitString "\n" s;

    in lines solution;

  makeOpamRepo = dir:
    let
      files = readDir dir;
      opamFiles = filterAttrsRecursive
        (name: value: isAttrs value || hasSuffix "opam" name) files;
      opamFilesOnly =
        converge (filterAttrsRecursive (_: v: v != { })) opamFiles;
      packages = concatLists (collect isList (mapAttrsRecursive
        (path': _: [rec {
          fileName = last path';
          dirName =
            splitNameVer (if init path' != [ ] then last (init path') else "");
          parsedOPAM = importOpam opamFile;
          name = parsedOPAM.name or (if hasSuffix ".opam" fileName then
            removeSuffix ".opam" fileName
          else
            dirName.name);

          version = parsedOPAM.version or (if dirName.version != "" then
            dirName.version
          else
            "dev");
          source = dir + ("/" + concatStringsSep "/" (init path'));
          opamFile = "${dir + ("/" + (concatStringsSep "/" path'))}";
        }]) opamFilesOnly));
      repo-description =
        namePathPair "repo" (toFile "repo" ''opam-version: "2.0"'');
      opamFileLinks = map ({ name, version, opamFile, ... }:
        namePathPair "packages/${name}/${name}.${version}/opam" opamFile)
        packages;
      pkgdefs = foldl (acc: x:
        recursiveUpdate acc { ${x.name} = { ${x.version} = x.parsedOPAM; }; })
        { } packages;
      sourceMap = foldl (acc: x:
        recursiveUpdate acc {
          ${x.name} = { ${x.version} = contentAddressedIFD x.source; };
        }) { } packages;
      repo = linkFarm "opam-repo" ([ repo-description ] ++ opamFileLinks);
    in repo // { passthru = { inherit sourceMap pkgdefs; }; };

  filterOpamRepo = packages: repo:
    linkFarm "opam-repo" ([ (namePathPair "repo" "${repo}/repo") ] ++ attrValues
      (mapAttrs (name: version:
        if isNull version then
          namePathPair "packages/${name}/${name}.dev"
          "${repo}/packages/${name}/${
            head (attrNames (readDir "${repo}/packages/${name}"))
          }"
        else
          namePathPair "packages/${name}/${name}.${version}"
          "${repo}/packages/${name}/${name}.${version}") packages))
    // optionalAttrs (repo ? passthru) {
      passthru = let
        pickRelevantVersions = from:
          mapAttrs (name: version: {
            ${if isNull version then "dev" else version} =
              if isNull version then
                head (attrValues from.${name})
              else
                from.${name}.${version};
          }) packages;
      in repo.passthru // mapAttrs (_: pickRelevantVersions) {
        inherit (repo.passthru) sourceMap pkgdefs;
      };

    };

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
          src = repo.passthru.sourceMap.${name}.${version};
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
  darwinOverlay = import ./overlays/ocaml-darwin.nix;
  opamRepository = args.opam-repository;

  __overlays = [
    (final: prev:
      defaultOverlay final prev
      // optionalAttrs prev.nixpkgs.stdenv.hostPlatform.isStatic
      (staticOverlay final prev)
      // optionalAttrs prev.nixpkgs.stdenv.hostPlatform.isDarwin
      (darwinOverlay final prev))
  ];

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

  materialize = { repos ? [ opamRepository ], env ? null }:
    query:
    pipe query [
      (opamList (joinRepos repos) env)
      (opamListToQuery)
      (queryToDefs repos)

      (mapAttrs (_: eraseStoreReferences))
      (mapAttrs (_: readFileContents))
      (toJSON)
      (toFile "package-defs.json")
    ];

  materializedDefsToScope =
    { pkgs ? bootstrapPackages, sourceMap ? { }, overlays ? __overlays }:
    defs:
    pipe defs [
      (readFile)
      (fromJSON)
      (mapAttrs (_: writeFileContents))
      (mapAttrs (_: injectSources sourceMap))

      (defsToScope pkgs)
      (applyOverlays overlays)
    ];

  queryToScope = { repos ? [ opamRepository ], pkgs ? bootstrapPackages
    , overlays ? __overlays, env ? defaultEnv }:
    query:
    pipe query [
      (opamList (joinRepos repos) env)
      (opamListToQuery)
      (queryToDefs repos)
      (defsToScope pkgs)
      (applyOverlays overlays)
    ];

  opamImport = { repos ? [ opamRepository ], pkgs ? bootstrapPackages
    , overlays ? __overlays }:
    export:
    let installedList = (importOpam export).installed;
    in pipe installedList [
      opamListToQuery
      (queryToDefs repos)
      (defsToScope pkgs)
      (applyOverlays overlays)
    ];

  getPinDepends = pkgdef:
    if pkgdef ? pin-depends then
      map (dep:
        let
          inherit (splitNameVer (head dep)) name version;

          fullUrl = (last dep);
          baseUrl = last (splitString "+" fullUrl); # Get rid of "git+"
          urlParts = splitString "#" baseUrl;
          url = head urlParts;
          rev = last urlParts;
          hasRev = length urlParts > 1;
          optionalRev = optionalAttrs hasRev { inherit rev; };
          allRefsOrWarn = if lib.versionAtLeast __nixVersion "2.4" then {
            allRefs = true;
          } else
            lib.warn
            "Nix version is too old for allRefs = true; fetching a repository may fail if the commit is on a non-master branch"
            { };
          path = builtins.fetchGit
            ({ inherit url; } // allRefsOrWarn // optionalRev);
          repo = filterOpamRepo { ${name} = null; } (makeOpamRepo path);
        in if !hasRev && !isImpure then
          lib.warn
          "pin-depends without an explicit sha1 is not supported in pure evaluation mode; try with --impure"
          bootstrapPackages.emptyDirectory
        else
          repo) pkgdef.pin-depends
    else
      [ ];

  buildOpamProject = { repos ? [ opamRepository ], pkgs ? bootstrapPackages
    , overlays ? __overlays, env ? defaultEnv, pinDepends ? true }@args:
    name: project: query:
    let
      repo = makeOpamRepo project;
      latestVersions = mapAttrs (_: last) (listRepo repo);

      pinDeps =
        getPinDepends repo.passthru.pkgdefs.${name}.${latestVersions.${name}};
    in queryToScope {
      repos = [ repo ] ++ optionals pinDepends pinDeps ++ repos;
      overlays = overlays;
      inherit pkgs env;
    } ({ ${name} = latestVersions.${name}; } // query);

  buildOpamProject' = { repos ? [ opamRepository ], pkgs ? bootstrapPackages
    , overlays ? __overlays, env ? defaultEnv, pinDepends ? true }@args:
    project: query:
    let
      repo = makeOpamRepo project;
      latestVersions = mapAttrs (_: last) (listRepo repo);

      pinDeps = concatLists (attrValues (mapAttrs
        (name: version: getPinDepends repo.passthru.pkgdefs.${name}.${version})
        latestVersions));
    in queryToScope {
      repos = [ repo ] ++ optionals pinDepends pinDeps ++ repos;
      overlays = overlays;
      inherit pkgs env;
    } (latestVersions // query);

  buildDuneProject = { pkgs ? bootstrapPackages, ... }@args:
    name: project: query:
    let
      generatedOpamFile = pkgs.pkgsBuildBuild.stdenv.mkDerivation {
        name = "${name}.opam";
        src = project;
        nativeBuildInputs = with pkgs.pkgsBuildBuild; [ dune_2 ocaml ];
        phases = [ "unpackPhase" "buildPhase" "installPhase" ];
        buildPhase = "dune build ${name}.opam";
        installPhase = ''
          rm _build -rf
          cp -R . $out
        '';
      };
    in buildOpamProject args name generatedOpamFile query;
}
