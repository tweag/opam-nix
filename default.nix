# Pkgset = { ${name} = { ${version} = Pkgdef; ... } ... }
# Pkgdef = { name = String; version = String; depends = [OpamVar]; build = ?[[String]]; install = ?[[String]]; ... }

pkgs:
let
  inherit (builtins)
    readDir mapAttrs concatStringsSep concatMap all isString isList elem
    attrValues filter attrNames head elemAt splitVersion foldl' fromJSON
    listToAttrs readFile getAttr toFile match isAttrs pathExists;
  inherit (pkgs) lib;
  inherit (lib)
    versionAtLeast splitString tail mapAttrs' nameValuePair zipAttrsWith collect
    filterAttrs unique subtractLists concatMapStringsSep concatLists reverseList
    fileContents pipe makeScope optionalAttrs filterAttrsRecursive hasSuffix
    converge mapAttrsRecursive hasAttr composeManyExtensions;

  readDirRecursive = dir:
    mapAttrs (name: type:
      if type == "directory" then readDirRecursive "${dir}/${name}" else type)
    (readDir dir);

  # [Pkgset] -> Pkgset
  mergePackageSets = zipAttrsWith (_: foldl' (a: b: a // b) { });

  bootstrapPackagesStub = import ./bootstrapPackages.nix { };

  bootstrapPackageNames = attrNames bootstrapPackagesStub;
in rec {
  # filterRelevant (traverseOPAMRepository ../../opam-repository) "opam-ed"
  opam2json = pkgs.ocaml-ng.ocamlPackages_4_09.callPackage ./opam2json.nix { };

  # Path -> {...}
  fromOPAM = opamFile:
    let
      json = pkgs.runCommandNoCC "opam.json" {
        preferLocalBuild = true;
        allowSubstitutes = false;
      } "${opam2json}/bin/opam2json ${opamFile} > $out";
    in fromJSON (readFile json);

  fromOPAM' = opamText: fromOPAM (toFile "opam" opamText);

  # Pkgdef -> Derivation
  pkgdef2drv = import ./pkgdef2drv.nix pkgs;

  # Path -> Derivation
  opam2nix = { opamFile, name ? null, version ? null }:
    pkgdef2drv (fromOPAM opamFile // { inherit name version; });

  splitNameVer = nameVer:
    let nv = nameVerToValuePair nameVer;
    in { inherit (nv) name version; };

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

  global-variables = import ./global-variables.nix pkgs;

  opamListToQuery = list: listToAttrs (map nameVerToValuePair list);

  opamList = repos: packages:
    let
      opam-root = pkgs.runCommand "opamroot" {
        nativeBuildInputs = [ pkgs.opam ];
        OPAMNO = "true";
      } ''
        export OPAMROOT=$out

        mkdir -p $NIX_BUILD_TOP/repos

        ${concatStringsSep "\n" (attrValues (mapAttrs (name: repo:
          "cp -R --no-preserve=all ${repo} $NIX_BUILD_TOP/repos/${name}")
          repos))}

        opam init --bare default $NIX_BUILD_TOP/repos/default --disable-sandboxing --disable-completion -n --bypass-checks
        ${concatStringsSep "\n" (attrValues (mapAttrs (name: repo:
          "opam repository add --set-default ${name} $NIX_BUILD_TOP/repos/${name}")
          (lib.filterAttrs (name: _: name != "default") repos)))}
      '';

      pkgRequest = name: version:
        if isNull version then name else "${name}.${version}";

      resolve-drv = pkgs.runCommand "resolve" {
        nativeBuildInputs = [ pkgs.opam ];
        OPAMNO = "true";
        OPAMCLI = "2.0";
      } ''
        export OPAMROOT=$NIX_BUILD_TOP/opam

        cp -R --no-preserve=all ${opam-root} $OPAMROOT

        opam list --resolve=${
          concatStringsSep "," (attrValues (mapAttrs pkgRequest packages))
        } --no-switch --short --with-test --depopts --columns=package > $out
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
      packages = collect isList (mapAttrsRecursive (path: _:
        let
          fileName = lib.last path;
          dirName = lib.last (lib.init path);
          # We try to avoid reading this opam file if possible
          name = if fileName == "opam" then
            (fromOPAM "${dir + ("/" + concatStringsSep "/" path)}").name or dirName
          else
            lib.removeSuffix ".opam" (lib.last path);

        in [
          {
            name = "sources/${name}/${name}.local";
            path = "${dir + ("/" + concatStringsSep "/" (lib.init path))}";
          }
          {
            name = "packages/${name}/${name}.local/opam";
            path = "${dir + ("/" + concatStringsSep "/" path)}";
          }
        ]) opamFilesOnly);
      repo-description = {
        name = "repo";
        path = toFile "repo" ''opam-version: "2.0"'';
      };
      repo = pkgs.linkFarm "opam-repo"
        ([ repo-description ] ++ concatLists packages);
    in repo;

  queryToDefs = repos: packages:
    let
      # default has the lowest prio
      repos' = (attrValues (filterAttrs (name: _: name != "default") repos))
        ++ [ repos.default ];

      findPackage = name: version:
        head (filter ({ opamFile, ... }: pathExists opamFile) (map (repo:
          let
            sourcePath = "${repo}/sources/${name}/${name}.local";
            isLocal = pathExists sourcePath;
            pkgDir = "${repo}/packages/${name}/${name}.${version}";
            filesPath = "${pkgDir}/files";
          in {
            opamFile = "${pkgDir}/opam";
            inherit name version isLocal repo;
            src = if isLocal then
              pkgs.runCommand "source-copy" { }
              "cp --no-preserve=all -R ${sourcePath}/ $out"
            else
              pkgs.emptyDirectory;
          } // optionalAttrs (pathExists filesPath) { files = filesPath; })
          repos'));

      packageFiles = mapAttrs findPackage packages;
    in mapAttrs
    (_: { opamFile, name, version, ... }@args: args // (fromOPAM opamFile))
    packageFiles;

  queryToDefs' = repos: packages:
    let
      # default has the lowest prio
      repos' = (attrValues (filterAttrs (name: _: name != "default") repos))
        ++ [ repos.default ];

      findPackage = name: version:
        head (filter ({ dir, ... }: pathExists dir) (map (repo: {
          dir = "${repo}/packages/${name}/${name}.${version}";
          inherit name version;
          src = repo.passthru.origSrc or pkgs.emptyDirectory;
        }) repos'));

      packageFiles = mapAttrs (_:
        { dir, name, version, src }:
        {
          inherit name version src;
          opamFile = "${dir}/opam";
        } // optionalAttrs (pathExists "${dir}/files") {
          files = "${dir}/files";
        }) (mapAttrs findPackage packages);

      readPackageFiles = ''
        (
        echo '['
        ${concatMapStringsSep ''

          echo ','
        '' ({ opamFile, name, version, src, files ? null }:
          ''
            opam2json ${opamFile} | jq '.name = "${name}" | .version = "${version}" | .opamFile = "${opamFile}" | .src = "${src}"${
              lib.optionalString (!isNull files) ''| .files = "${files}"''
            }' '') (attrValues packageFiles)}
        echo ']'
        ) > $out
      '';

      pkgdefs = pkgs.runCommand "opam2json-many.json" {
        nativeBuildInputs = [ opam2json pkgs.jq ];
      } readPackageFiles;

      listToAttrsByName = lst:
        listToAttrs (map (x: nameValuePair x.name x) lst);
    in listToAttrsByName (fromJSON (readFile pkgdefs));

  defsToScope = repos: pkgs: packages:
    makeScope pkgs.newScope (self:
      (mapAttrs (name: pkg: self.callPackage (pkgdef2drv pkg) { }) packages)
      // (import ./bootstrapPackages.nix pkgs
        packages.ocaml.version or packages.ocaml-base-compiler.version));

  defaultOverlay = import ./overlay.nix;

  applyOverlays = overlays: scope:
    scope.overrideScope' (composeManyExtensions overlays);

  queryToScope = { repos, pkgs, overlays ? [ defaultOverlay ] }:
    query:
    pipe query [
      (opamList repos)
      (opamListToQuery)
      (queryToDefs repos)
      (defsToScope repos pkgs)
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
        paths = attrValues (lib.getAttrs installedPackageNames set);
      };
    in combined;
}
