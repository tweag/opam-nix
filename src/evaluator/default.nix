lib:
let
  inherit (builtins)
    compareVersions elem elemAt replaceStrings head isString isList toJSON tail
    listToAttrs length attrValues mapAttrs concatStringsSep isBool isInt filter
    split foldl' match fromJSON;
  inherit (lib)
    splitString concatMap nameValuePair concatMapStringsSep all any zipAttrsWith
    zipListsWith optionalAttrs escapeShellArg hasInfix stringLength;

  inherit (import ../lib.nix lib) md5sri;
in rec {
  # Note: if you are using this evaluator directly, don't forget to source the setup
  setup = ./setup.sh;

  lexiCompare = a: b:
    if a == b then
      0
    else if isString a && hasInfix "~" a && stringLength a > stringLength b then
      -1
    else if isString a && hasInfix "~" b && stringLength a < stringLength b then
      1
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
  val = x: x.val or x;

  hasOpt' = opt: dep: elem opt dep.options or [ ];

  hasOpt = opt: hasOpt' { id = opt; };

  any' = pred: any (x: !isNull (pred x) && pred x);
  all' = pred: all (x: !isNull (pred x) && pred x);

  collectAllValuesFromOptionList = v:
    if isString v then
      [ v ]
    else if v ? val && isString v.val then
      [ v.val ]
    else if v ? val && isList v.val then
      concatMap collectAllValuesFromOptionList v.val
    else if isList v then
      concatMap collectAllValuesFromOptionList v
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

  envOpToShell = op: vals:
    let
      fst = (elemAt vals 0).id;
      snd = elemAt vals 1;
    in if op == "set" || op == "eq" then
      "${fst}=${escapeShellArg snd}"
    else if op == "prepend" then
      "${fst}=${escapeShellArg snd}\${${fst}+:}\${${fst}-}"
    else if op == "append" then
      "${fst}=\${${fst}-}\${${fst}+:}${escapeShellArg snd}"
    else if op == "prepend_trailing" then
      "${fst}=${escapeShellArg snd}:\${${fst}-}"
    else if op == "append_trailing" then
      "${fst}=\${${fst}-}:${escapeShellArg snd}"
    else
      throw "Operation ${op} not implemented";

  opToShell = op: vals:
    let
      fst = elemAt vals 0;
      snd = elemAt vals 1;
      fstS = toShellString fst;
      sndS = toShellString snd;
      fstC = toCondition fst;
      sndC = toCondition snd;
    in if op == "eq" then
      ''[ "$(compareVersions "${fstS}" "${sndS}")" = eq ]''
    else if op == "neq" then
      ''[ ! "$(compareVersions "${fstS}" "${sndS}")" = eq ]''
    else if op == "gt" then
      ''[ "$(compareVersions "${fstS}" "${sndS}")" = gt ]''
    else if op == "lt" then
      ''[ "$(compareVersions "${fstS}" "${sndS}")" = lt ]''
    else if op == "geq" then
      ''[ ! "$(compareVersions "${fstS}" "${sndS}")" = lt ]''
    else if op == "leq" then
      ''[ ! "$(compareVersions "${fstS}" "${sndS}")" = gt ]''
    else if op == "not" then
      "! ${fstC}"
    else if op == "and" then
      "${fstC} && ${sndC}"
    else if op == "or" then
      "${fstC} || ${sndC}"
    else
      throw "Operation ${op} not implemented";

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

  filterOptionList = vars:
    let
      getVar = x:
        if x ? id then lib.attrByPath (splitString ":" x.id) null vars else x;

      checkFilter = pkg: filter:
        if filter ? op && length filter.val == 1 then
          if filter.op == "not" then
            !checkFilter pkg (head filter.val)
          else if filter.op == "defined" then
            ! isNull (getVar (head filter.val))
          else
            compareVersions' filter.op (getVar { id = pkg; })
            (getVar (head filter.val))
        else if filter ? op then
          if filter.op == "and" then
            all' (checkFilter pkg) filter.val
          else if filter.op == "or" then
            any' (checkFilter pkg) filter.val
          else
            compareVersions' filter.op (getVar (head filter.val))
            (getVar (head (tail filter.val)))
        else if filter ? id then
          getVar filter
        else if isList filter then
          all' (checkFilter pkg) filter
        else
          throw "Couldn't understand package filter: ${toJSON filter}";

      collectAcceptableElements = v:
        let
          a = elemAt v.val 0;
          b = elemAt v.val 1;
          a' = collectAcceptableElements a;
          b' = collectAcceptableElements b;
        in if v ? op then
          if v.op == "or" then
            if a' != [ ] then a' else if b' != [ ] then b' else [ ]
          else if v.op == "and" then
            if a' != [ ] && b' != [ ] then a' ++ b' else [ ]
          else
            throw "Not a logop: ${v.op}"
        else if v ? options then
          if all' (checkFilter v.val) v.options then [ v ] else [ ]
        else if isString v then
          if !isNull (getVar { id = v; }) then [ v ] else [ ]
        else if isList v then
          concatMap collectAcceptableElements v
        else
          throw "Couldn't understand a part filtered package list: ${toJSON v}";

    in collectAcceptableElements;

  pkgVarsFor = name: lib.mapAttrs' (var: nameValuePair "${name}:${var}");

  varsToShell = vars:
    let
      v = attrValues (mapAttrs (name: value: ''
        ${varToShellVar name}="''${${varToShellVar name}-${toJSON value}}"
      '') vars);
    in concatStringsSep "" v;

  envToShell = env:
    concatMapStringsSep ""
    (concatMapStringsSep "\n" ({ op, val }: envOpToShell op val))
    (normalize' env);

  filterOptionListInShell = level: val:
    if val ? id then {
      type = "string";
      value = "$" + varToShellVar val.id;
    } else if val ? op then {
      type = "condition";
      value = opToShell val.op (map (x:
        if isList x then
          head (map (filterOptionListInShell level) x)
        else
          filterOptionListInShell level x) val.val);
    } else if val == [ ] then {
      type = "command";
      value = ":";
    } else if isList val then {
      type = "command";
      value = if level == 1 then
        "_ ${
          concatMapStringsSep " " (part:
            ''"${toShellString (filterOptionListInShell (level + 1) part)}"'')
          val
        }"
      else if level == 0 then
        concatMapStringsSep "\n"
        (part: toCommand (filterOptionListInShell (level + 1) part)) val
      else
        throw "Level too big";
    } else if val ? options then {
      type = "command";
      value = "if ${
          concatMapStringsSep " && "
          (x: toCondition (filterOptionListInShell level x)) val.options
        }; then ${toCommand (filterOptionListInShell level val.val)}; fi";
    } else {
      type = "string";
      value = interpolateStringsRec val;
    };

  filterSectionInShell = section:
    let s = filterOptionListInShell 0 (normalize section);
    in s.value;

  normalize = section:
    if !isList (val section) then
      [ [ section ] ]
    else if (val section) == [ ] || !isList (val (head (val section))) then
      [ section ]
    else
      section;

  normalize' = section:
    if !isList section then
      [ [ section ] ]
    else if section == [ ] || !isList (head section) then
      [ section ]
    else
      section;

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
    in optionalAttrs (!isNull m) { ${method} = head m; };

  # md5 is special in two ways:
  # nixpkgs only accepts it as an SRI,
  # and checksums without an explicit algo are assumed to be md5 in opam
  trymd5 = c:
    let
      m = match "md5=(.*)" c;
      m' = match "([0-9a-f]{32})" c;
      success = md5: { hash = md5sri (head md5); };
    in if !isNull m then success m else if !isNull m' then success m' else { };

  getHashes = checksums:
    zipAttrsWith (_: values: head values)
    (map (x: tryHash "sha512" x // tryHash "sha256" x // trymd5 x) checksums);
}
