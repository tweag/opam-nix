args:
let
  inherit (builtins)
    readDir
    mapAttrs
    concatStringsSep
    isString
    isList
    attrValues
    filter
    head
    foldl'
    fromJSON
    listToAttrs
    readFile
    toFile
    isAttrs
    pathExists
    toJSON
    deepSeq
    length
    sort
    concatMap
    attrNames
    match
    ;

  bootstrapPackages = args.pkgs;

  inherit (bootstrapPackages) lib;

  inherit (lib)
    splitString
    tail
    nameValuePair
    zipAttrsWith
    collect
    concatLists
    filterAttrsRecursive
    fileContents
    pipe
    makeScope
    optionalAttrs
    hasSuffix
    converge
    mapAttrsRecursive
    composeManyExtensions
    removeSuffix
    optionalString
    last
    init
    recursiveUpdate
    foldl
    optionals
    mapAttrsToList
    remove
    findSingle
    warn
    ;

  inherit (import ./evaluator lib)
    compareVersions'
    getUrl
    fetchWithoutChecksum
    singletonToList
    ;

  inherit (bootstrapPackages)
    runCommand
    linkFarm
    symlinkJoin
    opam2json
    opam
    ;

  # Pkgdef -> Derivation
  builder = import ./builder.nix bootstrapPackages.lib;

  contentAddressedIFD = dir: deepSeq (readDir dir) (/. + builtins.unsafeDiscardStringContext dir);

  global-variables = import ./global-variables.nix bootstrapPackages.stdenv.hostPlatform;

  defaultEnv = {
    inherit (global-variables)
      arch
      os
      os-family
      os-distribution
      os-version
      ;
    sys-ocaml-version = bootstrapPackages.ocaml-ng.ocamlPackages_latest.ocaml.version;
  };
  defaultResolveArgs = {
    env = defaultEnv;
    criteria = "-count[avoid-version,request],-count[avoid-version,changed],-count[version-lag,request],-count[version-lag,changed]";
    depopts = true;
    best-effort = false;
    dev = false;
    with-test = false;
    with-doc = false;
  };

  mergeSortVersions = zipAttrsWith (_: sort (compareVersions' "lt"));

  readFileContents =
    {
      files ? bootstrapPackages.emptyDirectory,
      ...
    }@def:
    (builtins.removeAttrs def [ "files" ])
    // {
      files-contents = mapAttrs (name: _: readFile (files + "/${name}")) (readDir files);
    };

  writeFileContents =
    {
      name ? "opam",
      files-contents ? { },
      ...
    }@def:
    (builtins.removeAttrs def [ "files-contents" ])
    // optionalAttrs (files-contents != { }) {
      files = symlinkJoin {
        name = "${name}-files";
        paths = (attrValues (mapAttrs bootstrapPackages.writeTextDir files-contents));
      };
    };

  eraseStoreReferences =
    def:
    (builtins.removeAttrs def [
      "repo"
      "opamFile"
      "src"
    ])
    // optionalAttrs (def ? src.url) {
      # Keep srcs which can be fetched
      src = {
        inherit (def.src) url rev subdir;
        hash = def.src.narHash;
      };
    };

  # Note: there can only be one version of the package present in packagedefs we're working on
  injectSources =
    sourceMap: def:
    if sourceMap ? ${def.name} then
      def // { src = sourceMap.${def.name}; }
    else if def ? src then
      def
      // {
        src = (bootstrapPackages.fetchgit { inherit (def.src) url rev hash; }) + def.src.subdir;
      }
    else
      def;
  namePathPair = name: path: { inherit name path; };
in
rec {

  /**
    `String → { name = String; version = String; }`

    Split opam's package definition (`name.version`) into components.
  */
  splitNameVer =
    nameVer:
    let
      nv = nameVerToValuePair nameVer;
    in
    {
      inherit (nv) name;
      version = nv.value;
    };

  /**
    `String → { name = String; value = String; }`

    Split opam's package definition (`name.version`) into components.
    Useful together with `listToAttrs`
  */
  nameVerToValuePair =
    nameVer:
    let
      split = splitString "." nameVer;
    in
    nameValuePair (head split) (concatStringsSep "." (tail split));

  /**
    `Path → { url? = { section = ...; } }`

    Read 'url' and 'checksum' from a separate file called 'url' if one exists.
    This supports the older opam repository format where this information was
    split out into a separate file rather than being part of the main `opam`
    file.
  */
  legacyUrlFileContents =
    opamFile:
    let
      urlPath = "${dirOf opamFile}/url";
    in
    if pathExists urlPath then
      let
        json = runCommand "url.json" {
          preferLocalBuild = true;
          allowSubstitutes = false;
        } "${opam2json}/bin/opam2json ${urlPath} > $out";
      in
      {
        url = {
          section = fromJSON (readFile json);
        };
      }
    else
      { };

  /**
    `Path -> {...}`

    Generate a nix attribute set from the opam file. This is just a Nix
    representation of the JSON produced by `opam2json`.
  */
  importOpam =
    opamFile:
    let
      isStorePath = p: !isNull (match "[0-9a-z]{32}-.*" p);
      dir = baseNameOf (dirOf opamFile);
      basename = baseNameOf opamFile;
      name =
        if !isStorePath basename && hasSuffix ".opam" basename then
          basename
        else if !isStorePath basename && !isStorePath dir then
          "${dir}.opam"
        else
          "opam";
      json = runCommand "${name}.json" {
        preferLocalBuild = true;
        allowSubstitutes = false;
      } "${opam2json}/bin/opam2json ${opamFile} > $out";
      opamContents = fromJSON (readFile json);

    in
    if (opamContents ? url) then
      opamContents
    else
      let
        urlFileContents = legacyUrlFileContents opamFile;
      in
      opamContents // urlFileContents;

  /**
    `String → {...}`

    Generate a nix attribute set from a string of opam. This is just a Nix
    representation of the JSON produced by `opam2json`.
  */
  fromOpam = opamText: importOpam (toFile "opam" opamText);

  /**
    ```
    { src = Path
    ; opamFile = ?Path
    ; name = ?String
    ; version = ?String
    ; resolveEnv = ?ResolveEnv }
    → Dependencies
    → Package
    ```

    Produce a callPackage-able `Package` from an opam file. This should be
    called using `callPackage` from a `Scope`. Note that you are
    responsible to ensure that the package versions in `Scope` are
    consistent with package versions required by the package. May be
    useful in conjunction with `opamImport`.
  */
  opam2nix =
    {
      src,
      opamFile ? src + "/${name}.opam",
      name ? null,
      version ? null,
      resolveEnv ? { },
    }:
    builder ({ inherit src name version; } // importOpam opamFile) resolveEnv;

  /**
    `Path → Dir`

    Like `builtins.readDir` but instead of `"directory"` each subdirectory is
    the attrset representing it.
  */
  readDirRecursive =
    dir:
    mapAttrs (name: type: if type == "directory" then readDirRecursive "${dir}/${name}" else type) (
      readDir dir
    );

  /**
    `Repository → {${package_name} = [version : String]}`

    Produce a mapping from package names to lists of versions (sorted
    older-to-newer) for an opam repository.
  */
  listRepo =
    repo:
    optionalAttrs (pathExists (repo + "/packages")) (
      mergeSortVersions (
        map (p: listToAttrs [ (nameVerToValuePair p) ]) (
          concatMap attrNames (attrValues (readDirRecursive (repo + "/packages")))
        )
      )
    );

  /**
    `[String] → Query`

    Turns a list of package versions produced by `opamList` into a "`Query`"
    with all the versions specified.
  */
  opamListToQuery = list: listToAttrs (map nameVerToValuePair list);

  opamList =
    repo: resolveArgs: packages:
    let
      pkgRequest =
        name: version:
        if version == "*" then
          name
        else if isNull version then
          (warn ''[opam-nix] Using `null' as a version in a query is deprecated, because it is unintuitive to the user. Use `"*"' instead.'' name)
        else
          "${name}.${version}";

      toString' = x: if isString x then x else toJSON x;

      args = recursiveUpdate defaultResolveArgs resolveArgs;

      environment = concatStringsSep "," (
        attrValues (mapAttrs (name: value: "${name}=${toString' value}") args.env)
      );

      query = concatStringsSep "," (attrValues (mapAttrs pkgRequest packages));

      resolve-drv =
        runCommand "resolve"
          {
            nativeBuildInputs = [
              opam
              bootstrapPackages.ocaml
            ];
            OPAMCLI = "2.0";
          }
          ''
            export OPAMROOT=$NIX_BUILD_TOP/opam

            cd ${repo}
            opam admin list \
              --resolve=${query} \
              --short \
              --columns=package \
              ${optionalString args.depopts "--depopts"} \
              ${optionalString args.dev "--dev"} \
              ${optionalString args.with-test "--with-test"} \
              ${optionalString args.with-doc "--doc"} \
              ${optionalString args.best-effort "--best-effort"} \
              ${optionalString (!isNull args.env) "--environment '${environment}'"} \
              ${optionalString (!isNull args.criteria) "--criteria='${args.criteria}'"} \
              | tee $out
          '';
      solution = fileContents resolve-drv;

      lines = s: splitString "\n" s;

    in
    lines solution;

  /**
    `Dir → Dir`

    Takes the attrset produced by `readDir` or `readDirRecursive`
    and leaves only `opam` files in (files named `opam` or `*.opam`).
  */
  filterOpamFiles =
    files:
    converge (filterAttrsRecursive (_: v: v != { })) (
      filterAttrsRecursive (
        name: value: isAttrs value || ((value == "regular" || value == "symlink") && hasSuffix "opam" name)
      ) files
    );

  /**
    `Path → Dir → Derivation`

    Takes the attrset produced by `filterOpamFiles` and produces a directory
    conforming to the `opam-repository` format.  The resulting derivation will
    also provide `passthru.sourceMap`, which is a map from package names to
    package sources taken from the original `Path`.
  */
  constructOpamRepo =
    root: opamFiles:
    let
      packages = concatLists (
        collect isList (
          mapAttrsRecursive (path': _: [
            rec {
              fileName = last path';
              dirName = splitNameVer (if init path' != [ ] then last (init path') else "");
              parsedOPAM = importOpam opamFile;
              name =
                parsedOPAM.name
                  or (if hasSuffix ".opam" fileName then removeSuffix ".opam" fileName else dirName.name);

              version = parsedOPAM.version or (if dirName.version != "" then dirName.version else "dev");
              subdir =
                "/"
                + concatStringsSep "/" (
                  let
                    i = init path';
                  in
                  if length i > 0 && last i == "opam" then init i else i
                );
              source = root + subdir;
              opamFile = "${root + ("/" + (concatStringsSep "/" path'))}";
              opamFileContents = readFile opamFile;
            }
          ]) opamFiles
        )
      );
      repo-description = namePathPair "repo" (toFile "repo" ''opam-version: "2.0"'');
      opamFileLinks = map (
        {
          name,
          version,
          opamFile,
          ...
        }:
        namePathPair "packages/${name}/${name}.${version}/opam" opamFile
      ) packages;
      pkgdefs = foldl (
        acc: x:
        recursiveUpdate acc {
          ${x.name} = {
            ${x.version} = x.parsedOPAM;
          };
        }
      ) { } packages;
      sourceMap = foldl (
        acc: x:
        recursiveUpdate acc {
          ${x.name} = {
            ${x.version} = (optionalAttrs (builtins.isAttrs root) root) // {
              inherit (x) subdir;
              outPath = contentAddressedIFD x.source;
            };
          };
        }
      ) { } packages;
      repo = linkFarm "opam-repo" ([ repo-description ] ++ opamFileLinks);
    in
    repo // { passthru = { inherit sourceMap pkgdefs; }; };

  makeOpamRepo' = recursive: if recursive then makeOpamRepoRec else makeOpamRepo;

  /**
    `Path → Derivation`

    Construct a directory conforming to the `opam-repository` format from
    a directory, taking opam files only from top-level and the `opam/`
    subdirectory.

    Also see all notes for `constructOpamRepo`.

    # Examples

    Build a package from a local directory, which depends on packages from opam-repository:

    ```nix
    let
      repos = [ (makeOpamRepo ./.) opamRepository ];
      scope = queryToScope { inherit repos; } { my-package = "*"; };
    in scope.my-package
    ```
  */
  makeOpamRepo =
    dir:
    let
      contents = readDir dir;
      contents' = (
        contents
        // optionalAttrs (contents.opam or null == "directory") {
          opam = readDir "${dir}/opam";
        }
      );
    in
    constructOpamRepo dir (filterOpamFiles contents');

  /**
    `Path → Derivation`

    Construct a directory conforming to the `opam-repository` format from a
    directory, looking for opam files recursively. Note that this is not what
    `opam install` does, but it may be more convenient in some cases.

    Also see all notes for `constructOpamRepo`.
  */
  makeOpamRepoRec = dir: constructOpamRepo dir (filterOpamFiles (readDirRecursive dir));

  /**
    `String → String → Repository → Path`

    Find an opam package (constrained by `name` and `version`) in an opam repository (`repo`).
  */
  findPackageInRepo =
    name: version: repo:
    let
      pkgDirVariants = [
        (repo + "/packages/${name}.${version}")
        (repo + "/packages/${name}/${name}.${version}")
      ];

      headOrNull = lst: if length lst == 0 then null else head lst;

      pkgDir = headOrNull (filter (pathExists) pkgDirVariants);
    in
    pkgDir;

  /**
    `Query → Repository → Repository`

    Filters the repository to only include packages (and their particular
    versions) present in the supplied Query.

    FIXME: if the repo is formatted like packages/name.version, version defaulting will not work
  */
  filterOpamRepo =
    packages: repo:
    linkFarm "opam-repo" (
      [ (namePathPair "repo" "${repo}/repo") ]
      ++ attrValues (
        mapAttrs (
          name: version:
          let
            defaultPath = "${repo}/packages/${name}/${head (attrNames (readDir "${repo}/packages/${name}"))}";
          in
          if version == "*" || isNull version then
            namePathPair "packages/${name}/${name}.dev" defaultPath
          else
            namePathPair "packages/${name}/${name}.${version}" (
              let
                path = findPackageInRepo name version repo;
              in
              if !isNull path then path else defaultPath
            )
        ) packages
      )
    )
    // optionalAttrs (repo ? passthru) {
      passthru =
        let
          pickRelevantVersions =
            from:
            mapAttrs (name: version: {
              ${if version == "*" || isNull version then "dev" else version} =
                if version == "*" || isNull version then
                  head (attrValues from.${name})
                else
                  from.${name}.${version} or (head (attrValues from.${name}));
            }) packages;
        in
        repo.passthru
        // mapAttrs (_: pickRelevantVersions) {
          inherit (repo.passthru) sourceMap pkgdefs;
        };

    };

  /**
    `[Repository] → Query → Defs`

    Takes a query (with all the version specified, e.g. produced by
    `opamListToQuery` or by reading the `installed` section of `opam.export`
    file) and produces an attribute set of package definitions (using
    `importOpam`).
  */
  queryToDefs =
    repos: packages:
    let
      findPackage =
        name: version:
        let
          pkgDir = findPackageInRepo name version;

          filesPath = contentAddressedIFD (pkgDir repo + "/files");
          repos' = filter (repo: repo ? passthru.pkgdefs.${name}.${version} || !isNull (pkgDir repo)) repos;
          repo =
            if length repos' > 0 then
              head repos'
            else
              throw "[opam-nix] Could not find package ${name}.${version} in any repository. Checked:\n  - ${concatStringsSep "\n  - " repos}";
          isLocal = repo ? passthru.sourceMap;
        in
        {
          opamFile = pkgDir repo + "/opam";
          inherit
            name
            version
            isLocal
            repo
            ;
        }
        // optionalAttrs (pathExists (pkgDir repo + "/files")) {
          files = filesPath;
        }
        // optionalAttrs isLocal {
          src = repo.passthru.sourceMap.${name}.${version};
          pkgdef = repo.passthru.pkgdefs.${name}.${version};
        };

      packageFiles = mapAttrs findPackage packages;
    in
    mapAttrs (
      _:
      {
        opamFile,
        name,
        version,
        ...
      }@args:
      (builtins.removeAttrs args [ "pkgdef" ]) // args.pkgdef or (importOpam opamFile)
    ) packageFiles;

  /**
    `callPackageWith` from Nixpkgs, but without all the fancy stuff.
  */
  callPackageWith =
    autoArgs: fn: args:
    let
      f =
        if lib.isAttrs fn then
          fn
        else if lib.isFunction fn then
          fn
        else
          import fn;
      auto = builtins.intersectAttrs (f.__functionArgs or (builtins.functionArgs f)) autoArgs;
    in
    lib.makeOverridable f (auto // args);

  /**
    `Nixpkgs → ResolveEnv → Defs → Scope`

    Takes a nixpkgs instantiataion, a resolve environment and an attribute set
    of definitions (as produced by `queryToDefs`) and produces a `Scope`.
  */
  defsToScope =
    pkgs: resolveEnv: defs:
    makeScope callPackageWith (
      self:
      (mapAttrs (name: pkg: self.callPackage (builder pkg resolveEnv) { }) defs)
      // {
        nixpkgs = pkgs.extend (_: _: { inherit opam2json; });
      }
    );

  defaultOverlay = import ./overlays/ocaml.nix;
  staticOverlay = import ./overlays/ocaml-static.nix;
  darwinOverlay = import ./overlays/ocaml-darwin.nix;
  opamRepository = args.opam-repository;
  opamOverlays = args.opam-overlays;
  mirageOpamOverlays = args.mirage-opam-overlays;

  __overlays = [
    (
      final: prev:
      defaultOverlay final prev
      // optionalAttrs prev.nixpkgs.stdenv.hostPlatform.isStatic (staticOverlay final prev)
      // optionalAttrs prev.nixpkgs.stdenv.hostPlatform.isDarwin (darwinOverlay final prev)
    )
  ];

  /**
    `[Overlay] → Scope → Scope`

    Applies a list of overlays to a scope.
  */
  applyOverlays = overlays: scope: scope.overrideScope (composeManyExtensions overlays);

  /**
    `{ with-test : ?Bool, with-doc : ?Bool, ... } → Query → Scope`

    Applies `with-test` and `with-doc` to all packages in `Scope` which are
    specified in the `Query`.
  */
  applyChecksDocs =
    {
      with-test ? defaultResolveArgs.with-test,
      with-doc ? defaultResolveArgs.with-doc,
      ...
    }:
    query: scope:
    scope.overrideScope (
      _: prev:
      mapAttrs (
        name: _:
        prev.${name}.overrideAttrs (_: {
          doCheck = with-test;
          doDoc = with-doc;
        })
      ) query
    );
  /**
    `[Repository] → Repository`

    Merges multiple repositories together.
  */
  joinRepos =
    repos:
    if length repos == 0 then
      runCommand "empty-repo" { } "mkdir -p $out/packages"
    else if length repos == 1 then
      head repos
    else
      symlinkJoin {
        name = "opam-repo";
        paths = repos;
      };

  /**
    ```
    { repos = ?[Repository]
    ; resolveArgs = ?ResolveArgs
    ; regenCommand = ?String}
    → Query
    → Path
    ```

    Resolves a query in much the same way as `queryToScope` would, but instead
    of producing a scope it produces a JSON file containing all the package
    definitions for the packages required by the query.
  */
  materialize =
    {
      repos ? [ opamRepository ],
      resolveArgs ? { },
      regenCommand ? null,
    }:
    query:
    pipe query [
      (opamList (joinRepos repos) resolveArgs)
      (opamListToQuery)
      (queryToDefs repos)

      (mapAttrs (_: eraseStoreReferences))
      (mapAttrs (_: readFileContents))
      (d: d // { __opam_nix_regen = regenCommand; })
      (d: d // { __opam_nix_env = resolveArgs.env or { }; })
      (toJSON)
      (toFile "package-defs.json")
    ];

  /**
    ```
    { repos = ?[Repository]
    ; resolveArgs = ?ResolveArgs
    ; pinDepends = ?Boolean
    ; regenCommand = ?[String]}
    → project : Path
    → Query
    → Path
    ```

    A wrapper around `materialize`, similar to `buildOpamProject` (which
    is a wrapper around `queryToScope`), but again instead of producing a
    scope it produces a JSON file with all the package definitions. It also
    handles `pin-depends` unless it is passed `pinDepends = false`, just like
    `buildOpamProject`.
  */
  materializeOpamProject =
    {
      repos ? [ opamRepository ],
      resolveArgs ? { },
      regenCommand ? null,
      pinDepends ? true,
      recursive ? false,
    }:
    name: project: query:
    let
      repo = makeOpamRepo' recursive project;
      latestVersions = mapAttrs (_: last) (listRepo repo);
      pkgdef = repo.passthru.pkgdefs.${name}.${latestVersions.${name}};

      pinDeps = getPinDepends pkgdef project;
      pinDepsQuery = pinDependsQuery pkgdef;
    in
    materialize {
      repos = [ repo ] ++ optionals pinDepends pinDeps ++ repos;
      resolveArgs = {
        dev = true;
      }
      // resolveArgs;
      inherit regenCommand;
    } ({ ${name} = latestVersions.${name}; } // pinDepsQuery // query);

  /**
    ```
    { repos = ?[Repository]
    ; resolveArgs = ?ResolveArgs
    ; pinDepends = ?Boolean
    ; regenCommand = ?[String]}
    → project : Path
    → Query
    → Path
    ```

    Similar to `materializeOpamProject` but adds all packages found in the project
    directory. Like `buildOpamProject` compared to `buildOpamProject'`.
  */

  materializeOpamProject' =
    {
      repos ? [ opamRepository ],
      resolveArgs ? { },
      regenCommand ? null,
      pinDepends ? true,
      recursive ? false,
    }:
    project: query:
    let
      repo = makeOpamRepo' recursive project;
      latestVersions = mapAttrs (_: last) (listRepo repo);

      pinDeps = concatLists (
        attrValues (
          mapAttrs (
            name: version: getPinDepends repo.passthru.pkgdefs.${name}.${version} project
          ) latestVersions
        )
      );
      pinDepsQuery = foldl' recursiveUpdate { } (
        attrValues (
          mapAttrs (name: version: pinDependsQuery repo.passthru.pkgdefs.${name}.${version}) latestVersions
        )
      );
    in
    materialize {
      repos = [ repo ] ++ optionals pinDepends pinDeps ++ repos;
      resolveArgs = {
        dev = true;
      }
      // resolveArgs;
      inherit regenCommand;
    } (latestVersions // pinDepsQuery // query);

  /**
    ```
    { pkgs = ?Nixpkgs
    ; overlays = ?[Overlay] }
    → Path
    → Scope
    ```

    Takes a JSON file with package definitions as produced by `materialize` and
    turns it into a scope. It is quick, does not use IFD or have any dependency
    on `opam` or `opam2json`. Note that `opam2json` is still required for
    actually building the package (it parses the `<package>.config` file).
  */
  materializedDefsToScope =
    {
      pkgs ? bootstrapPackages,
      sourceMap ? { },
      overlays ? __overlays,
    }:
    file:
    let
      defs = pipe file [
        (readFile)
        (fromJSON)
        (d: removeAttrs d [ "__opam_nix_regen" ])
      ];
      env =
        defs.__opam_nix_env
          or (warn "[opam-nix] Your package-defs.json file is missing __opam_nix_env. Please, re-generate it."
            { }
          );
    in
    pipe defs [
      (d: removeAttrs d [ "__opam_nix_env" ])
      (mapAttrs (_: writeFileContents))
      (mapAttrs (_: injectSources sourceMap))

      (defsToScope pkgs env)
      (applyOverlays overlays)
    ];

  /**
    ```
    { repos = ?[Repository]
    ; pkgs = ?Nixpkgs
    ; overlays = ?[Overlay]
    ; resolveArgs = ?ResolveArgs }
    → Query
    → Scope
    ```

    ```
    ResolveEnv : { ${var_name} = value : String; ... }
    ```

    ```
    ResolveArgs :
    { env = ?ResolveEnv
    ; with-test = ?Bool
    ; with-doc = ?Bool
    ; dev = ?Bool
    ; depopts = ?Bool
    ; best-effort = ?Bool
    }
    ```

    Turn a `Query` into a `Scope`.

    Special value of `"*"` can be passed as a version in the `Query` to
    let opam figure out the latest possible version for the package.

    The first argument allows providing custom repositories & top-level
    nixpkgs, adding overlays and passing an environment to the resolver.

    # `repos`, `env` & version resolution

    Versions are resolved using upstream opam. The passed repositories
    (`repos`, containing `opam-repository` by default) are merged and then
    `opam admin list --resolve` is called on the resulting
    directory. Package versions from earlier repositories take precedence
    over package versions from later repositories. `env` allows to pass
    additional "environment" to `opam admin list`, affecting its version
    resolution decisions. See [`man
    opam-admin`](https://opam.ocaml.org/doc/man/opam-admin.html) for
    further information about the environment.

    When a repository in `repos` is a derivation and contains
    `passthru.sourceMap`, sources for packages taken from that repository
    are taken from that source map.

    # `pkgs` & `overlays`

    By default, `pkgs` match the `pkgs` argument to `opam.nix`, which, in
    turn, is the `nixpkgs` input of the flake. `overlays` default to
    `defaultOverlay` and `staticOverlay` in case the passed nixpkgs appear
    to be targeting static building.

    # Examples

    Build a package from `opam-repository`, using all sane defaults:

    ```nix
    (queryToScope { } { opam-ed = "*"; ocaml-system = "*"; }).opam-ed
    ```

    Build a specific version of the package, overriding some dependencies:

    ```nix
    let
      scope = queryToScope { } { opam-ed = "0.3"; ocaml-system = "*"; };
      overlay = self: super: {
        opam-file-format = super.opam-file-format.overrideAttrs
          (oa: { opam__ocaml__native = "true"; });
      };
    in (scope.overrideScope overlay).opam-ed
    ```

    Pass static nixpkgs (to get statically linked libraries and
    executables):

    ```nix
    let
      scope = queryToScope {
        pkgs = pkgsStatic;
      } { opam-ed = "*"; ocaml-system = "*"; };
    in scope.opam-ed
    ```
  */
  queryToScope =
    {
      repos ? [ opamRepository ],
      pkgs ? bootstrapPackages,
      overlays ? __overlays,
      resolveArgs ? { },
    }:
    query:
    pipe query [
      (opamList (joinRepos repos) resolveArgs)
      (opamListToQuery)
      (queryToDefs repos)
      (defsToScope pkgs resolveArgs.env or { })
      (applyOverlays overlays)
      (applyChecksDocs resolveArgs query)
    ];

  /**
    ```
    { repos = ?[Repository]
    ; pkgs = ?Nixpkgs
    ; overlays = ?[Overlay] }
    → Path
    → Scope
    ```

    Import an opam switch, similarly to `opam import`, and provide a package
    combining all the packages installed in that switch. `repos`, `pkgs`,
    `overlays` and `Scope` are understood identically to `queryToScope`, except
    no version resolution is performed.
  */
  opamImport =
    {
      repos ? [ opamRepository ],
      pkgs ? bootstrapPackages,
      resolveArgs ? { },
      overlays ? __overlays,
    }:
    export:
    let
      installedList = (importOpam export).installed;
    in
    pipe installedList [
      opamListToQuery
      (queryToDefs repos)
      (defsToScope pkgs resolveArgs.env or { })
      (applyOverlays overlays)
      (applyChecksDocs resolveArgs (opamListToQuery installedList))
    ];

  /**
    `Pkgdef → [Repository]`

    Takes a package definition and produces the list of repositories corresponding
    to `pin-depends` of the packagedefs. Requires `--impure` (to fetch the repos
    specified in `pin-depends`). Each repository includes only one package.
  */
  getPinDepends =
    pkgdef: project:
    map (
      dep:
      let
        inherit (splitNameVer (head dep)) name version;
      in
      filterOpamRepo { ${name} = version; } (makeOpamRepo (fetchWithoutChecksum (last dep) project))
    ) (singletonToList pkgdef.pin-depends or [ ]);

  /**
    `Pkgdef → Query`

    Takes a package definition and produces a query containing all the pinned packages.
  */
  pinDependsQuery =
    pkgdef:
    listToAttrs (
      map (
        dep:
        let
          inherit (splitNameVer (head dep)) name version;
        in
        {
          inherit name;
          value = version;
        }
      ) (singletonToList pkgdef.pin-depends or [ ])
    );

  /**
    { repos = ?[Repository]
    ; pkgs = ?Nixpkgs
    ; overlays = ?[Overlay]
    ; resolveArgs = ?ResolveArgs
    ; pinDepends = ?Bool
    ; recursive = ?Bool }
    → name: String
    → project: Path
    → Query
    → Scope

    A convenience wrapper around `queryToScope`.

    Turn an opam project (found in the directory passed as the third argument) into
    a `Scope`. More concretely, produce a scope containing the package called `name`
    from the `project` directory, together with other packages from the `Query`.

    Analogous to `opam install .`.

    The first argument is the same as the first argument of `queryToScope`, except
    the repository produced by calling `makeOpamRepo` on the project directory is
    prepended to `repos`. An additional `pinDepends` attribute can be supplied. When
    `true`, it pins the dependencies specified in `pin-depends` of the packages in
    the project.

    `recursive` controls whether subdirectories are searched for opam files (when
    `true`), or only the top-level project directory and the `opam/` subdirectory
    (when `false`).

    #### Examples

    Build a package from a local directory:

    ```nix
    (buildOpamProject { } "my-package" ./. { }).my-package

    Build a package from a local directory, forcing opam to use the
    non-"system" compiler:

    ```nix
    (buildOpamProject { } "my-package" ./. { ocaml-base-compiler = "*"; }).my-package
    ```

    Building a statically linked library or binary from a local directory:

    ```nix
    (buildOpamProject { pkgs = pkgsStatic; } "my-package" ./. { }).my-package
    ```
    Build a project with tests:

    ```nix
    (buildOpamProject { resolveArgs.with-test = true; } "my-package" ./. { }).my-package
    ```
  */
  buildOpamProject =
    {
      repos ? [ opamRepository ],
      pkgs ? bootstrapPackages,
      overlays ? __overlays,
      resolveArgs ? { },
      pinDepends ? true,
      recursive ? false,
    }@args:
    name: project: query:
    let
      repo = makeOpamRepo' recursive project;
      latestVersions = mapAttrs (_: last) (listRepo repo);
      pkgdef = repo.passthru.pkgdefs.${name}.${latestVersions.${name}};

      pinDeps = getPinDepends pkgdef project;
      pinDepsQuery = pinDependsQuery pkgdef;
    in
    queryToScope {
      repos = [ repo ] ++ optionals pinDepends pinDeps ++ repos;
      overlays = overlays;
      resolveArgs = {
        dev = true;
      }
      // resolveArgs;
      inherit pkgs;
    } ({ ${name} = latestVersions.${name}; } // pinDepsQuery // query);

  /**
    ```
    { repos = ?[Repository]
    ; pkgs = ?Nixpkgs
    ; overlays = ?[Overlay]
    ; resolveArgs = ?ResolveArgs
    ; pinDepends = ?Bool
    ; recursive = ?Bool }
    → project: Path
    → Query
    → Scope
    ```

    Similar to `buildOpamProject`, but adds all packages found in the
    project directory to the resulting `Scope`.

    #### Examples

    Build a package from a local directory:

    ```nix
    (buildOpamProject' { } ./. { }).my-package
    ```
  */

  buildOpamProject' =
    {
      repos ? [ opamRepository ],
      pkgs ? bootstrapPackages,
      overlays ? __overlays,
      resolveArgs ? { },
      pinDepends ? true,
      recursive ? false,
    }@args:
    project: query:
    let
      repo = makeOpamRepo' recursive project;
      latestVersions = mapAttrs (_: last) (listRepo repo);

      pinDeps = concatLists (
        attrValues (
          mapAttrs (
            name: version: getPinDepends repo.passthru.pkgdefs.${name}.${version} project
          ) latestVersions
        )
      );
      pinDepsQuery = foldl' recursiveUpdate { } (
        attrValues (
          mapAttrs (name: version: pinDependsQuery repo.passthru.pkgdefs.${name}.${version}) latestVersions
        )
      );
    in
    queryToScope {
      repos = [ repo ] ++ optionals pinDepends pinDeps ++ repos;
      overlays = overlays;
      resolveArgs = {
        dev = true;
      }
      // resolveArgs;
      inherit pkgs;
    } (latestVersions // pinDepsQuery // query);

  /**
    ```
    { repos = ?[Repository]
    ; pkgs = ?Nixpkgs
    ; overlays = ?[Overlay]
    ; resolveArgs = ?ResolveArgs }
    → name: String
    → project: Path
    → Query
    → Scope
    ```

    A convenience wrapper around `buildOpamProject`. Behaves exactly as
    `buildOpamProject`, except runs `dune build ${name}.opam` in an
    environment with `dune_3` and `ocaml` from nixpkgs beforehand. This is
    supposed to be used with dune's `generate_opam_files`

    #### Examples

    Build a local project which uses dune and doesn't have an opam file:

    ```nix
    (buildDuneProject { } "my-package" ./. { }).my-package
    ```
  */
  buildDuneProject =
    {
      pkgs ? bootstrapPackages,
      dune ? pkgs.pkgsBuildBuild.dune_3,
      ...
    }@args:
    name: project: query:
    let
      generatedOpamFile = pkgs.pkgsBuildBuild.stdenv.mkDerivation {
        name = "${name}.opam";
        src = project;
        nativeBuildInputs = [
          dune
          pkgs.pkgsBuildBuild.ocaml
        ];
        phases = [
          "unpackPhase"
          "buildPhase"
          "installPhase"
        ];
        buildPhase = "dune build ${name}.opam";
        installPhase = ''
          rm _build -rf
          cp -R . $out
        '';
      };
    in
    buildOpamProject args name generatedOpamFile query;

  /**
    `Defs → Sources`

    Takes an attribute set of definitions (as produced by `queryToDefs`) and
    produces a list `Sources` (`[ { name; version; src; } ... ]`).
  */
  defsToSrcs =
    filterPkgs: defs:
    let
      # use our own version of lib.strings.nameFromURL without `assert name != filename`
      nameFromURL =
        url: sep:
        let
          components = splitString "/" url;
          filename = last components;
          name = head (splitString sep filename);
        in
        name;
      defToSrc =
        { version, ... }@pkgdef:
        let
          inherit (getUrl bootstrapPackages pkgdef) src;
          name =
            let
              n = nameFromURL pkgdef.dev-repo ".";
            in
            # rename dune so it doesn't clash with dune file in duniverse
            if n == "dune" then "_dune" else n;
        in
        # filter out pkgs without dev-repos
        if pkgdef ? dev-repo then { inherit name version src; } else { };
      # remove filterPkgs
      filteredDefs = removeAttrs defs filterPkgs;
      srcs = mapAttrsToList (pkgName: def: defToSrc def) filteredDefs;
      # remove empty elements from pkgs without dev-repos
      cleanedSrcs = remove { } srcs;
    in
    cleanedSrcs;

  /**
    `Sources → Sources`

    Deduplicates `Sources` produced by `defsToSrcs`, as some packages may share
    sources if they are developed in the same repo.
  */
  deduplicateSrcs =
    srcs:
    # This is O(n^2). We could try and improve this by sorting the list on name. But n is small.
    let
      op =
        srcs: newSrc:
        # Find if two packages come from the same dev-repo.
        # Note we are assuming no dev-repos will have different names here, but we also assume
        # this later when we will symlink in the duniverse directory based on this name.
        let
          duplicateSrc = findSingle (src: src.name == newSrc.name) null "multiple" srcs;
        in
        # Multiple duplicates should never be found as we deduplicate on every new element.
        assert duplicateSrc != "multiple";
        if duplicateSrc == null then
          srcs
          ++ [
            newSrc
          ]
        # > If packages from the same repo were resolved to different URLs, we need to pick
        # > a single one. Here we decided to go with the one associated with the package
        # > that has the higher version. We need a better long term solution as this won't
        # > play nicely with pins for instance.
        # > The best solution here would be to use source trimming, so we can pull each individual
        # > package to its own directory and strip out all the unrelated source code but we would
        # > need dune to provide that feature.
        # See [opam-monorepo](https://github.com/tarides/opam-monorepo/blob/9262e7f71d749520b7e046fbd90a4732a43866e9/lib/duniverse.ml#L143-L157)
        else if duplicateSrc.version >= newSrc.version then
          srcs
        else
          (remove duplicateSrc srcs) ++ [ newSrc ];
    in
    foldl' op [ ] srcs;

  /**
    `Sources → Scope`

    Takes `Sources` and creates an attribute set mapping package names to
    sources with a derivation that fetches the source at the `src` URL.
  */
  mkMonorepo =
    srcs:
    let
      # derivation that fetches the source
      mkSrc =
        {
          name,
          version,
          src,
        }:
        bootstrapPackages.pkgsBuildBuild.stdenv.mkDerivation ({
          inherit name version src;
          phases = [
            "unpackPhase"
            "installPhase"
          ];
          installPhase = ''
            mkdir $out
            cp -R . $out
          '';
        });
    in
    listToAttrs (map (src: nameValuePair src.name (mkSrc src)) srcs);

  /**
    ```
    { repos = ?[Repository]
    ; resolveArgs = ?ResolveArgs
    ; filterPkgs ?[ ] }
    → Query
    → Scope
    ```

    Similar to `queryToScope`, but creates a attribute set (instead of a
    scope) with package names mapping to sources for replicating the
    [`opam monorepo`](https://github.com/tarides/opam-monorepo) workflow.

    The `filterPkgs` argument gives a list of package names to filter from
    the resulting attribute set, rather than removing them based on their
    opam `dev-repo` name.
  */
  queryToMonorepo =
    {
      repos ? [
        mirageOpamOverlays
        opamOverlays
        opamRepository
      ],
      resolveArgs ? { },
      filterPkgs ? [ ],
    }:
    query:
    pipe query [
      # pass monorepo = 1 to pick up dependencies marked with {?monorepo}
      # TODO use opam monorepo solver to filter non-dune dependant packages
      (opamList (joinRepos repos) (recursiveUpdate resolveArgs { env.monorepo = 1; }))
      opamListToQuery
      (queryToDefs repos)
      (defsToSrcs filterPkgs)
      deduplicateSrcs
      mkMonorepo
    ];

  /**
    ```
    { repos = ?[Repository]
    ; resolveArgs = ?ResolveArgs
    ; pinDepends = ?Bool
    ; recursive = ?Bool
    ; extraFilterPkgs ?[ ] }
    → project: Path
    → Query
    → Sources
    ```

    A convenience wrapper around `queryToMonorepo`.

    Creates a monorepo for an opam project (found in the directory passed
    as the second argument). The monorepo consists of an attribute set of
    opam package `dev-repo`s to sources, for all dependancies of the
    packages found in the project directory as well as other packages from
    the `Query`.

    The packages in the project directory are excluded from
    the resulting monorepo along with `ocaml-system`, `opam-monorepo`, and
    packages in the `extraFilterPkgs` argument.
  */
  buildOpamMonorepo =
    {
      repos ? [
        mirageOpamOverlays
        opamOverlays
        opamRepository
      ],
      resolveArgs ? { },
      pinDepends ? true,
      recursive ? false,
      extraFilterPkgs ? [ ],
    }@args:
    project: query:
    let
      repo = makeOpamRepo' recursive project;
      latestVersions = mapAttrs (_: last) (listRepo repo);

      pinDeps = concatLists (
        attrValues (
          mapAttrs (
            name: version: getPinDepends repo.passthru.pkgdefs.${name}.${version} project
          ) latestVersions
        )
      );
    in
    queryToMonorepo {
      repos = [ repo ] ++ optionals pinDepends pinDeps ++ repos;
      filterPkgs = [
        "ocaml-system"
        "opam-monorepo"
      ]
      ++
        # filter all queried packages, and packages with sources
        # in the project, from the monorepo
        (attrNames latestVersions)
      ++ extraFilterPkgs;
      resolveArgs = {
        dev = true;
      }
      // resolveArgs;
    } (latestVersions // query);

  /**
    ```
    { repos = ?[Repository]
    ; resolveArgs = ?ResolveArgs
    ; filterPkgs ?[ ]
    ; regenCommand = ?[String]}
    → Query
    → Scope
    ```

    Resolves a query in much the same way as `queryToMonorepo` would, but instead
    of producing an attribute set it produces a JSON file containing all the package
    definitions for the packages required by the query.
  */
  materializeQueryToMonorepo =
    {
      repos ? [
        mirageOpamOverlays
        opamOverlays
        opamRepository
      ],
      resolveArgs ? { },
      filterPkgs ? [ ],
      regenCommand ? null,
    }:
    query:
    pipe query [
      # pass monorepo = 1 to pick up dependencies marked with {?monorepo}
      # TODO use opam monorepo solver to filter non-dune dependant packages
      (opamList (joinRepos repos) (recursiveUpdate resolveArgs { env.monorepo = 1; }))
      opamListToQuery
      (queryToDefs repos)
      (defs: removeAttrs defs filterPkgs)
      (mapAttrs (_: eraseStoreReferences))
      (mapAttrs (_: readFileContents))
      (d: d // { __opam_nix_regen = regenCommand; })
      (toJSON)
      (toFile "monorepo-defs.json")
    ];

  /**
    ```
    { repos = ?[Repository]
    ; resolveArgs = ?ResolveArgs
    ; pinDepends = ?Bool
    ; recursive = ?Bool
    ; extraFilterPkgs ?[ ]
    ; regenCommand = ?[String]} }
    → project: Path
    → Query
    → Sources
    ```

    A wrapper around `materializeQueryToMonorepo`, similar to `buildOpamMonorepo` (which
    is a wrapper around `queryToMonorepo`), but again instead of producing an
    attribute set it produces a JSON file with all the package definitions. It also
    handles `pin-depends` unless it is passed `pinDepends = false`, just like
    `buildOpamMonorepo`.
  */
  materializeBuildOpamMonorepo =
    {
      repos ? [
        mirageOpamOverlays
        opamOverlays
        opamRepository
      ],
      resolveArgs ? { },
      pinDepends ? true,
      recursive ? false,
      extraFilterPkgs ? [ ],
      regenCommand ? null,
    }:
    project: query:
    let
      repo = makeOpamRepo' recursive project;
      latestVersions = mapAttrs (_: last) (listRepo repo);

      pinDeps = concatLists (
        attrValues (
          mapAttrs (
            name: version: getPinDepends repo.passthru.pkgdefs.${name}.${version} project
          ) latestVersions
        )
      );
    in
    materializeQueryToMonorepo {
      repos = [ repo ] ++ optionals pinDepends pinDeps ++ repos;
      filterPkgs = [
        "ocaml-system"
        "opam-monorepo"
      ]
      ++
        # filter all queried packages, and packages with sources
        # in the project, from the monorepo
        (attrNames latestVersions)
      ++ extraFilterPkgs;
      resolveArgs = {
        dev = true;
      }
      // resolveArgs;
      inherit regenCommand;
    } (latestVersions // query);

  /**
    ```
    { pkgs = ?Nixpkgs }
    → Path
    → Scope
    ```

    Takes a JSON file with monorepo definition as produced by `materializeQmaterializeQueryToMonorepo` and
    turns it into an attribute set.
  */
  unmaterializeQueryToMonorepo =
    {
      pkgs ? bootstrapPackages,
      sourceMap ? { },
      filterPkgs ? [ ],
    }:
    file:
    let
      defs = pipe file [
        (readFile)
        (fromJSON)
        (d: removeAttrs d [ "__opam_nix_regen" ])
      ];
    in
    pipe defs [
      (mapAttrs (_: writeFileContents))
      (mapAttrs (_: injectSources sourceMap))
      (defsToSrcs filterPkgs)
      deduplicateSrcs
      mkMonorepo
    ];
}
