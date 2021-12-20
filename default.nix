# SPDX-FileCopyrightText: 2020 Serokell <https://serokell.io>
#
# SPDX-License-Identifier: MPL-2.0

# Pkgset = { ${name} = { ${version} = Pkgdef; ... } ... }
# Pkgdef = { name = String; version = String; depends = [OpamVar]; build = ?[[String]]; install = ?[[String]]; ... }

pkgs:
let
  inherit (builtins)
    readDir mapAttrs concatStringsSep concatMap all isString isList elem
    attrValues filter attrNames head elemAt splitVersion foldl' fromJSON;
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

  bootstrapPackages = import ./bootstrapPackages.nix { };

  bootstrapPackageNames = attrNames bootstrapPackages;
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
    in builtins.fromJSON (builtins.readFile json);

  # Pkgdef -> Derivation
  pkgdef2drv = (import ./pkgdef2drv.nix pkgs).pkgdeftodrv;

  # Path -> Derivation
  opam2nix = { opamFile, name ? null, version ? null }:
    pkgdef2drv (fromOPAM opamFile // { inherit name version; });

  # Path -> Pkgset
  traverseOPAMRepository = repo:
    let
      contents = readDirRecursive "${repo}/packages";
      opam-version = (fromOPAM "${repo}/repo").opam-version or "2.0";

      splitNameVer = nameVer:
        concatStringsSep "." (tail (splitString "." nameVer));

      contents' = mapAttrs (name:
        mapAttrs' (namever: v:
          nameValuePair (splitNameVer namever)
          (fromOPAM "${repo}/packages/${name}/${namever}/opam" // {
            inherit name;
            version = splitNameVer namever;
          }))) contents;
    in assert versionAtLeast opam-version "2.0";
    mapAttrs (_: flattenVersions) contents';

  flattenVersions = v:
    let
      sortedVersions =
        lib.sort (a: b: (builtins.compareVersions a.version b.version) == -1)
        (attrValues v);
    in builtins.listToAttrs (lib.zipListsWith
      (a: b: lib.nameValuePair a.version (a // { cudfVersion = toString b; }))
      sortedVersions
      (builtins.genList (lib.add 1) (builtins.length sortedVersions)));

  # An optimization to prevent evaluating everything in the repository
  filterRelevant = set: name:
    let
      resolveDepend = dep:
        if isString dep then
          [ dep ]
        else
          concatMap (x: if isString x.val then [ x.val ] else x.val) (collect
            (x:
              x ? val
              && (isString x.val || (isList x.val && all isString x.val))) dep);

      go = done: todo:
        let
          name = head todo;
          todo' = tail todo;
          done' = [ name ] ++ done;
        in if builtins.length todo == 0 then
          done
        else
          go done' (subtractLists done' (unique (todo'
            ++ (concatMap (p: concatMap resolveDepend p.depends or [ ])
              (attrValues set.${name})))));

      relevant = go [ ] [ name ];
    in filterAttrs (x: _: elem x relevant) set;

  # (Op | Options | String) -> [[String]]
  flattenOps = set: name: vars: d:
    if d ? op then
      if d.op == "and" then
        concatMap (flattenOps set name vars) d.val
      else if d.op == "or" then
        [ (concatLists (concatMap (flattenOps set name vars) d.val)) ]
      else if d.op == "not" then
        [ ]
      else if ops ? ${d.op} then
        let
          ver = head d.val;
          ver' = if ver ? id then vars.${ver.id} else ver;
        in [
          [
            "${renderPname name} ${ops.${d.op}} ${
              set.${name}.${ver'}.cudfVersion or "1"
            }"
          ]
        ]
      else
        throw "Unknown op ${d.op}"
    else if d ? options then
      concatMap (flattenOps set d.val vars) d.options
    else if d ? id then
      [ [ (renderPname name) ] ]
    else if isList d then
      concatMap (flattenOps set name vars) d
    else # Just plain package
      [ [ (renderPname d) ] ];

  ops = {
    eq = "=";
    gt = ">";
    lt = "<";
    geq = ">=";
    leq = "<=";
    neq = "!=";
  };

  global-variables = import ./global-variables.nix pkgs;

  cudfDepends = set: p:
    concatMapStringsSep ", " (dep:
      concatMapStringsSep ", " (concatStringsSep " | ")
      (flattenOps set p.name (global-variables // p) dep)) (p.depends or [ ]);

  isDigits = c: isString c && !isNull (builtins.match "[0-9]*" c);

  trimZeroes = c:
    let trimmed = head (builtins.match "[0]*([0-9]*)" c);
    in if trimmed == "" then "0" else trimmed;

  renderPname = builtins.replaceStrings [ "_" ] [ "-" ];

  # You can't have multiple versions of the same package installed simultaneously, so package conflicts with self
  pkgdef2cudf = set: p:
    ''
      package: ${renderPname p.name}
      version: ${p.cudfVersion}
      conflicts: ${renderPname p.name}
    '' + lib.optionalString (p ? depends) ''
      depends: ${cudfDepends set p}
    '';

  # Pkgset -> String -> String -> { ${name} = Pkgdef; }
  resolveVersions = set: name: version:
    let
      universe = concatMapStringsSep "\n" (pkgdef2cudf set)
        (collect (x: x ? name && x ? version) set);

      request = ''

        request: ${name}
        install: ${renderPname name} = ${set.${name}.${version}.cudfVersion}
      '';
    in universe + request;
}
