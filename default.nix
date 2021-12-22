# SPDX-FileCopyrightText: 2020 Serokell <https://serokell.io>
#
# SPDX-License-Identifier: MPL-2.0

# Pkgset = { ${name} = { ${version} = Pkgdef; ... } ... }
# Pkgdef = { name = String; version = String; depends = [OpamVar]; build = ?[[String]]; install = ?[[String]]; ... }

pkgs:
let
  inherit (builtins)
    readDir mapAttrs concatStringsSep concatMap all isString isList elem
    attrValues filter attrNames head elemAt splitVersion foldl' fromJSON
    listToAttrs readFile getAttr;
  inherit (pkgs) lib;
  inherit (lib)
    versionAtLeast splitString tail pipe mapAttrs' nameValuePair zipAttrsWith
    collect filterAttrs unique subtractLists concatMapStringsSep concatLists
    reverseList;

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

  # Pkgdef -> Derivation
  pkgdef2drv = (import ./pkgdef2drv.nix pkgs).pkgdeftodrv;

  # Path -> Derivation
  opam2nix = { opamFile, name ? null, version ? null }:
    pkgdef2drv (fromOPAM opamFile // { inherit name version; });

  splitNameVer = nameVer:
    let split = splitString "." nameVer;
    in {
      name = head split;
      version = concatStringsSep "." (tail split);
    };

  ops = {
    eq = "=";
    gt = ">";
    lt = "<";
    geq = ">=";
    leq = "<=";
    neq = "!=";
  };

  global-variables = import ./global-variables.nix pkgs;

  opamListToQuery = list:
    listToAttrs
    (map (line: let nv = splitNameVer line; in nameValuePair nv.name nv.version)
      list);

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
          "opam repository add ${name} $NIX_BUILD_TOP/repos/${name}")
          (lib.filterAttrs (name: _: name != "default") repos)))}
      '';

      pkgRequest = name: version:
        if isNull version then name else "${name}.${version}";

      resolve-drv = pkgs.runCommand "resolve" {
        nativeBuildInputs = [ pkgs.opam ];
        OPAMNO = "true";
      } ''
        export OPAMROOT=$NIX_BUILD_TOP/opam

        cp -R --no-preserve=all ${opam-root} $OPAMROOT

        opam list --resolve=${
          concatStringsSep "," (attrValues (mapAttrs pkgRequest packages))
        } --no-switch --short --with-test --depopts --columns=package > $out
      '';
      solution = lib.fileContents resolve-drv;

      lines = s: splitString "\n" s;

    in lines solution;

  dirExists = dir:
    let
      path = tail (splitString "/" (builtins.unsafeDiscardStringContext dir));
      folded = foldl' ({ exists, p ? null }:
        component:
        if exists then {
          exists = (readDir "/${p}").${component} or null == "directory";
          p = "${p}/${component}";
        } else {
          exists = false;
        }) {
          exists = true;
          p = "";
        } path;
    in path != [ ] && folded.exists;

  queryToDefs = repos: packages:
    let
      # default has the lowest prio
      repos' = (attrValues (lib.filterAttrs (name: _: name != "default") repos))
        ++ [ repos.default ];

      findPackage = name: version:
        head (filter ({ dir, ... }: dirExists dir) (map (repo: {
          dir = "${repo}/packages/${name}/${name}.${version}";
          inherit name version;
        }) repos'));

      packageFiles = mapAttrs (_:
        { dir, name, version }:
        {
          inherit name version;
          opamFile = "${dir}/opam";
        } // lib.optionalAttrs (dirExists "${dir}/files") {
          files = "${dir}/files";
        }) (mapAttrs findPackage packages);

    in mapAttrs (_:
      { opamFile, name, version, ... }@args:
      args // (fromOPAM opamFile)) packageFiles;

  defsToScope = repos: bootstrap: packages:
    lib.makeScope pkgs.newScope (self:
      (mapAttrs (name: pkg: self.callPackage (pkgdef2drv pkg) { }) packages)
      // (import ./bootstrapPackages.nix bootstrap));

  queryToScope = repos: bootstrap: query:
    lib.pipe query [
      (opamList repos)
      (opamListToQuery)
      (queryToDefs repos)
      (defsToScope repos bootstrap)
    ];

  opamImport = repos: bootstrap: export:
    lib.pipe export [
      (fromOPAM)
      (getAttr "installed")
      (opamListToQuery)
      (queryToDefs repos)
      (defsToScope repos bootstrap)
    ];

}
