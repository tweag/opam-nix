lib:
let
  inherit (builtins)
    compareVersions elem elemAt replaceStrings head isString isList toJSON tail
    listToAttrs length attrValues mapAttrs concatStringsSep isBool isInt filter
    split foldl' match fromJSON stringLength genList concatLists nixVersion throw;
  inherit (lib)
    splitString concatMap nameValuePair concatMapStringsSep all any zipAttrsWith
    zipListsWith optionalAttrs optional escapeShellArg hasInfix
    stringToCharacters flatten last warn path;

  inherit (import ../lib.nix lib) md5sri;

  isImpure = builtins ? currentSystem;
in rec {
  # Note: if you are using this evaluator directly, don't forget to source the setup
  setup = ./setup.sh;

  chrcmp = a: b:
    if a == b then
      0
    else if a == "~" && b != "~" then
      (-1)
    else if a != "~" && b == "~" then
      1
    else if a > b then
      1
    else
      (-1);
  strcmp = a: b:
    let
      a' = stringToCharacters a ++ [ "" ];
      b' = stringToCharacters b ++ [ "" ];
    in head (filter (x: x != 0) (zipListsWith chrcmp a' b'));

  lexiCompare = a: b:
    if a == b then
      0
    else if isString a && (hasInfix "~" a || hasInfix "~" b) then
      strcmp a b
    else if a > b then
      1
    else
      (-1);

  trimZeroes = s: head (match ("[0]*([0-9]+)") s);

  compareVersions' = op: a: b:
    let
      prepareVersion = version:
        map (x: if isList x then fromJSON (trimZeroes (head x)) else x)
        (split "([0-9]+)" version);
      comp' = filter (x: x != 0)
        (zipListsWith lexiCompare (prepareVersion a) (prepareVersion b));
      comp = if comp' == [ ] then 0 else head comp';
    in if isNull a || isNull b then
      false
    else if op == "eq" then
      a == b
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

  any' = pred: any (x: !isNull (pred x) && pred x);
  all' = pred: all (x: !isNull (pred x) && pred x);

  collectAllValuesFromOptionList = v:
    if isString v then
      [ v ]
    else if v ? conditions then
      collectAllValuesFromOptionList v.val
    else if v ? logop then
      collectAllValuesFromOptionList v.lhs
      ++ collectAllValuesFromOptionList v.rhs
    else if isList v then
      concatMap collectAllValuesFromOptionList v
    else if v ? group then
      concatMap collectAllValuesFromOptionList v.group
    else
      throw "unexpected dependency: ${toJSON v}";

  functionArgsFor = pkgdef:
    let
      # Get _all_ dependencies mentioned in the opam file

      allDepends = collectAllValuesFromOptionList pkgdef.depends or [ ];
      allDepopts = collectAllValuesFromOptionList pkgdef.depopts or [ ];

      genArgs = deps: optional:
        listToAttrs (map (name: nameValuePair name optional) deps);
    in genArgs allDepends false // genArgs allDepopts true;

  envOpToShell = v@{ lhs, rhs, ... }:
    if v.relop or null == "eq" || v.env_update == "set" then
      "${lhs.id}=${escapeShellArg rhs}"
    else if v.env_update == "prepend" then
      "${lhs.id}=${escapeShellArg rhs}\${${lhs.id}+:}\${${lhs.id}-}"
    else if v.env_update == "append" then
      "${lhs.id}=\${${lhs.id}-}\${${lhs.id}+:}${escapeShellArg rhs}"
    else if v.env_update == "prepend_trailing" then
      "${lhs.id}=${escapeShellArg rhs}:\${${lhs.id}-}"
    else if v.env_update == "append_trailing" then
      "${lhs.id}=\${${lhs.id}-}:${escapeShellArg rhs}"
    else
      throw "Operation ${v.env_update} not implemented";

  varToShellVar = var:
    let s = splitString ":" var;
    in concatMapStringsSep "__" (replaceStrings [ "-" "+" "." ] [ "_" "_" "_" ])
    ([ "opam" ] ++ s);

  toShellString = { type, value }:
    if type == "string" then
      value
    else if type == "command" then
      "$(${value})"
    else
      throw "Can't convert ${type} to shell string";
  toCommand = { type, value }:
    if type == "command" then
      value
    else if type == "string" then
      ''echo "${value}"''
    else
      throw "Can't convert ${type} to command";
  toCondition = { type, value }@x:
    if type == "condition" then
      value
    else
      ''[[ "${toShellString x}" == true ]]'';

  filterPackageFormula = vars:
    let
      getVar = id: lib.attrByPath (splitString ":" id) null vars;

      getVersion = x:
        if x ? id then
          getVar x.id
        else if isString x then
          x
        else
          throw "Not a valid version description: ${toJSON x}";

      toString' = value:
        if value == true then "true"
        else if value == false then "false"
        else toString value;

      checkVersionFormula = pkg: filter:
        if filter ? pfxop then
          if filter.pfxop == "not" then
            let r = checkVersionFormula pkg filter.arg;
            in if isNull r then null else !r
          else if filter.pfxop == "defined" then
            vars ? filter.arg.id
          else
            throw "Unknown pfxop ${filter.pfxop}"
        else if filter ? logop then
          if filter.logop == "and" then
            all' (checkVersionFormula pkg) [ filter.lhs filter.rhs ]
          else if filter.logop == "or" then
            any' (checkVersionFormula pkg) [ filter.lhs filter.rhs ]
          else
            throw "Unknown logop ${filter.logop}"
        else if filter ? prefix_relop then
          compareVersions' filter.prefix_relop (getVar pkg)
          (getVersion filter.arg)
        else if filter ? relop then
          compareVersions' filter.relop (toString' (getVersion filter.lhs))
          (toString' (getVersion filter.rhs))
        else if filter ? id then
          getVar filter.id
        else if isList filter then
          all' (checkVersionFormula pkg) filter
        else if filter ? group then
          all' (checkVersionFormula pkg) filter.group
        else
          throw "Couldn't understand package condition: ${toJSON filter}";

      filterPackageFormulaRec = v: let
        lhs' = filterPackageFormulaRec v.lhs;
        rhs' = filterPackageFormulaRec v.rhs;
      in if v ? logop then
        if v.logop == "or" then
          if lhs' != [ ] then lhs' else if rhs' != [ ] then rhs' else [ ]
        else if v.logop == "and" then
          if lhs' != [ ] && rhs' != [ ] then flatten [ lhs' rhs' ] else [ ]
        else
          throw "Unknown logop ${v.logop}"
      else if v ? conditions then
        if all' (checkVersionFormula v.val) v.conditions then
          filterPackageFormulaRec v.val
        else
          [ ]
      else if isString v then
        if !isNull (getVar v) then v else [ ]
      else if isList v then
        map filterPackageFormulaRec v
      else if v ? group then
        flatten (map filterPackageFormulaRec v.group)
      else
        throw "Couldn't understand a part of filtered list: ${toJSON v}";
    in v: flatten (filterPackageFormulaRec v);

  filterOptionList = vars:
    let
      getVar = id: lib.attrByPath (splitString ":" id) null vars;

      getVersion = x:
        if x ? id then
          getVar x.id
        else if isString x then
          x
        else
          throw "Not a valid version description: ${toJSON x}";

      checkVersionFormula = pkg: filter:
        if filter ? pfxop then
          if filter.pfxop == "not" then
            let r = checkVersionFormula pkg filter.arg;
            in if isNull r then null else !r
          else if filter.pfxop == "defined" then
            vars ? filter.arg.id
          else
            throw "Unknown pfxop ${filter.pfxop}"
        else if filter ? logop then
          if filter.logop == "and" then
            all' (checkVersionFormula pkg) [ filter.lhs filter.rhs ]
          else if filter.logop == "or" then
            any' (checkVersionFormula pkg) [ filter.lhs filter.rhs ]
          else
            throw "Unknown logop ${filter.logop}"
        else if filter ? relop then
          compareVersions' filter.relop (getVersion filter.lhs)
          (getVersion filter.rhs)
        else if filter ? id then
          getVar filter.id
        else if isList filter then
          all' (checkVersionFormula pkg) filter
        else if filter ? group then
          all' (checkVersionFormula pkg) filter.group
        else
          throw "Couldn't understand option list condition: ${toJSON filter}";

      filterOptionListRec = v: if v ? conditions then
        if all' (checkVersionFormula v.val) v.conditions then
          filterOptionListRec v.val
        else
          [ ]
      else if isString v then
        v
      else if isList v then
        map filterOptionListRec v
      else if v ? group then
        flatten (map filterOptionListRec v.group)
      else
        throw "Couldn't understand a part of filtered list: ${toJSON v}";
    in v: flatten (filterOptionListRec v);

  pkgVarsFor = name: lib.mapAttrs' (var: nameValuePair "${name}:${var}");

  varsToShell = vars:
    let
      v = attrValues (mapAttrs (name: value: ''
        ${varToShellVar name}="''${${varToShellVar name}-${toJSON value}}"
      '') vars);
    in concatStringsSep "" v;

  envToShell = env: concatMapStringsSep "\n" envOpToShell (flatten (if isList env then env else [env]));

  filterOptionListInShell = level: val:
    if val ? id then
      let
        s = splitString ":" val.id;
        pkgs = splitString "+" (head s);
        isEnable = last s == "enable";
        trueish = if isEnable then "enable" else "true";
        falseish = if isEnable then "disable" else "false";
      in {
        type = "string";
        value = if length pkgs == 1 then
          "\${${varToShellVar val.id}}"
        else
          "$(if ${
            concatMapStringsSep " && " (pkg:
              "[[ \${${
                varToShellVar (concatStringsSep ":" ([ pkg ] ++ tail s))
              }} == ${trueish} ]]") pkgs
          }; then echo ${trueish}; else echo ${falseish}; fi)";
      }
    else if val ? relop || val ? logop then {
      type = "condition";
      value = let
        op = val.relop or val.logop;
        lhsS = toShellString (filterOptionListInShell level val.lhs);
        rhsS = toShellString (filterOptionListInShell level val.rhs);
        lhsC = toCondition (filterOptionListInShell level val.lhs);
        rhsC = toCondition (filterOptionListInShell level val.rhs);
      in if op == "eq" then
        ''[ "$(compareVersions "${lhsS}" "${rhsS}")" = eq ]''
      else if op == "neq" then
        ''[ ! "$(compareVersions "${lhsS}" "${rhsS}")" = eq ]''
      else if op == "gt" then
        ''[ "$(compareVersions "${lhsS}" "${rhsS}")" = gt ]''
      else if op == "lt" then
        ''[ "$(compareVersions "${lhsS}" "${rhsS}")" = lt ]''
      else if op == "geq" then
        ''[ ! "$(compareVersions "${lhsS}" "${rhsS}")" = lt ]''
      else if op == "leq" then
        ''[ ! "$(compareVersions "${lhsS}" "${rhsS}")" = gt ]''
      else if op == "and" then
        "${lhsC} && ${rhsC}"
      else if op == "or" then
        "${lhsC} || ${rhsC}"
      else
        throw "Unknown op ${op}";
    } else if val ? pfxop then {
      type = "condition";
      value = if val.pfxop == "not" then
        "! ${toCondition (filterOptionListInShell level val.arg)}"
        # else if val.pfxop == "defined" then
        #   "[[ -n ${val.arg.} ]]"
      else
        throw "Unknown pfxop ${val.pfxop}";
    } else if val == [ ] then {
      type = "command";
      value = ":";
    } else if isList val then {
      type = "command";
      value = if level == 1 then
        concatMapStringsSep " " (part:
          ''"${toShellString (filterOptionListInShell (level + 1) part)}"'')
        val
      else if level == 0 then
        concatMapStringsSep "\n"
        (part: toCommand (filterOptionListInShell (level + 1) part)) val
      else
        throw "Level too big";
    } else if val ? conditions then {
      type = "command";
      value = "if ${
          concatMapStringsSep " && "
          (x: toCondition (filterOptionListInShell level x)) val.conditions
        }; then ${toCommand (filterOptionListInShell level val.val)}; fi";
    } else if isString val then {
      type = "string";
      value = interpolateStringsRec val;
    } else if val ? group then
      filterOptionListInShell level (head val.group)
    else
      throw "Can't convert ${toJSON val} to shell commands";

  filterSectionInShell = section:
    let
      val = x: x.val or x;
      normalize = section:
        if !isList (val section) then
          [ [ section ] ]
        else if (val section) == [ ] || !isList (val (head (val section))) then
          [ section ]
        else
          section;
      s = filterOptionListInShell 0 (normalize section);
    in s.value;

  interpolateStringsRec = val:
    if isString val then
      interpolateString val
    else if isList val then
      map interpolateStringsRec val
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
      throw "Don't know how to toString ${toJSON v}";

  # FIXME this should be implemented correctly and not using regex
  interpolateString = s:
    let
      pieces = filter isString (split "([%][{]|[}][%])" s);
      result = foldl' ({ i, result }:
        piece: {
          i = !i;
          result = result + (if i then
            toShellString (filterOptionListInShell 2 { id = piece; })
          else
            piece);
        }) {
          i = false;
          result = "";
        } pieces;
    in if length pieces == 1 then s else result.result;

  tryHash = method: c:

    let m = match "${method}=(.*)" c;
    in optional (!isNull m) { ${method} = head m; };

  # md5 is special in two ways:
  # nixpkgs only accepts it as an SRI,
  # and checksums without an explicit algo are assumed to be md5 in opam
  trymd5 = c:
    let
      m = match "md5=(.*)" c;
      m' = match "([0-9a-f]{32})" c;
      success = md5: [{ hash = md5sri (head md5); }];
    in if !isNull m then success m else if !isNull m' then success m' else [ ];

  getHashes = checksums:
    head (concatMap (x: tryHash "sha512" x ++ tryHash "sha256" x ++ trymd5 x)
      checksums ++ [ { } ]);

  fetchGitURL = fullUrl:
    let
      baseUrl = last (splitString "+" fullUrl); # Get rid of "git+"
      urlParts = splitString "#" baseUrl;
      url = head urlParts;
      ref = last urlParts;
      hasRef = length urlParts > 1;
      isRev = s: !isNull (builtins.match "[0-9a-f]{40}" s);
      hasRev = hasRef && isRev ref;
      optionalRev = optionalAttrs hasRev { rev = ref; };
      refsOrWarn = if hasRef && !isRev ref then {
        inherit ref;
      } else if lib.versionAtLeast nixVersion "2.4" then {
        allRefs = true;
      } else
        warn
        "[opam-nix] Nix version is too old for allRefs = true; fetching a repository may fail if the commit is on a non-master branch"
        { };
      path = (builtins.fetchGit ({
        inherit url;
        submodules = true;
      } // refsOrWarn // optionalRev)) // {
        inherit url;
      };
    in
      if !hasRev && !isImpure then
        throw
        "[opam-nix] a git dependency without an explicit sha1 is not supported in pure evaluation mode; try with --impure"
      else path;

  fetchImpure = url: project:
    let splitUrl = splitString "+" (head (splitString ":" url)); in
    let proto = if length splitUrl > 1 then head splitUrl else null; in
    if proto == "git" then fetchGitURL url
    else if proto == "http" || proto == "https" then builtins.fetchTarball url
    # if no protocol assume a local file path
    else if proto == null &&
      # absolute path
      !path.subpath.isValid url then /. + url
    else if proto == null && project != null then
      # relative path (note '..' is not accepted)
      path.append project url
    else throw "[opam-nix] Protocol '${proto}' is not yet supported";

  getUrl = pkgs: pkgdef:
    let
      hashes = if pkgdef.url.section ? checksum then
        if isList pkgdef.url.section.checksum then
          getHashes pkgdef.url.section.checksum
        else
          getHashes [ pkgdef.url.section.checksum ]
      else
        { };
      archive = pkgdef.url.section.src or pkgdef.url.section.archive or "";
      src = if pkgdef ? url then
      # Default unpacker doesn't support .zip
        if hashes == { } then
          fetchImpure archive null
        else
          pkgs.fetchurl ({ url = archive; } // hashes)
      else
        pkgdef.src or pkgs.pkgsBuildBuild.emptyDirectory;
    in { inherit archive src; };

}
