lib:
let
  inherit (builtins)
    compareVersions elem elemAt replaceStrings head isString isList toJSON tail
    listToAttrs length attrValues mapAttrs concatStringsSep isBool isInt filter
    split foldl' match;
  inherit (lib)
    splitString concatMap nameValuePair concatMapStringsSep all any zipAttrsWith
    optionalAttrs escapeShellArg;

  inherit (import ./lib.nix lib) md5sri;
in rec {

  fixVersion = replaceStrings [ "~" ] [ "" ];
  compareVersions' = op: a: b:
    let comp = compareVersions (fixVersion a) (fixVersion b);
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

  collectAllDeps = v:
    if isString v then
      [ v ]
    else if v ? val && isString v.val then
      [ v.val ]
    else if v ? val && isList v.val then
      concatMap collectAllDeps v.val
    else if isList v then
      concatMap collectAllDeps v
    else
      throw "unexpected dependency: ${toJSON v}";

  functionArgsFor = pkgdef:
    let
      # Get _all_ dependencies mentioned in the opam file

      allDepends = collectAllDeps pkgdef.depends or [ ];
      allDepopts = collectAllDeps pkgdef.depopts or [ ];

      genArgs = deps: optional:
        listToAttrs (map (name: nameValuePair name optional) deps);
    in genArgs allDepends false // genArgs allDepopts true;

  envOpToBash = op: vals:
    let
      fst = (elemAt vals 0).id;
      snd = elemAt vals 1;
    in if op == "set" || op == "eq" then
      "export ${fst}=${escapeShellArg snd}"
    else if op == "prepend" then
      "export ${fst}=${escapeShellArg snd}\${${fst}+:}\${${fst}-}"
    else if op == "append" then
      "export ${fst}=\${${fst}-}\${${fst}+:}${escapeShellArg snd}"
    else if op == "prepend_trailing" then
      "export ${fst}=${escapeShellArg snd}:\${${fst}-}"
    else if op == "append_trailing" then
      "export ${fst}=\${${fst}-}:${escapeShellArg snd}"
    else
      throw "Operation ${op} not implemented";

  opToBash = op: vals:
    let
      fst = elemAt vals 0;
      snd = elemAt vals 1;
      fstS = toShellString fst;
      sndS = toShellString snd;
      fstC = toCondition fst;
      sndC = toCondition snd;
    in if op == "eq" then
      ''[ "${fstS}" = "${sndS}" ]''
    else if op == "gt" then
      ''
        ( [ ! "${fstS}" = "${sndS}" ] && [ "${sndS}" = "$(( echo "${fstS}"; echo "${sndS}" ) | sort -V | head -n1)" ] )''
    else if op == "lt" then
      ''
        ( [ ! "${fstS}" = "${sndS}" ] && [ "${fstS}" = "$(( echo "${fstS}"; echo "${sndS}" ) | sort -V | head -n1)" ] )''
    else if op == "geq" then
      ''
        [ "${sndS}" = "$(( echo "${fstS}"; echo "${sndS}" ) | sort -V | head -n1)" ]''
    else if op == "leq" then
      ''
        [ "${sndS}" = "$(( echo "${fstS}"; echo "${sndS}" ) | sort -V | head -n1)" ]''
    else if op == "neq" then
      ''[ ! "${fstS}" = "${sndS}" ]''
    else if op == "not" then
      "! ${fstC}"
    else if op == "and" then
      "${fstC} && ${sndC}"
    else if op == "or" then
      "${fstC} || ${sndC}"
    else
      throw "Operation ${op} not implemented";

  opamVarToShellVar = var:
    let s = splitString ":" var;
    in concatMapStringsSep "__" (replaceStrings [ "-" ] [ "_" ])
    ([ "opam" ] ++ s);

  toShellString = { type, value }:
    if type == "string" then
      value
    else if type == "command" then
      "$(${value})"
    else
      throw "Can't convert ${type} to bash string";
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
  relevantDepends = vars:
    let
      getVar = x:
        if x ? id then lib.attrByPath (splitString ":" x.id) null vars else x;

      checkPackageFilter = pkg: filter:
        if filter ? op && length filter.val == 1 then
          if filter.op == "not" then
            !checkPackageFilter pkg (head filter.val)
          else
            compareVersions' filter.op (getVar { id = pkg; })
            (getVar (head filter.val))
        else if filter ? op then
          if filter.op == "and" then
            all' (checkPackageFilter pkg) filter.val
          else if filter.op == "or" then
            any' (checkPackageFilter pkg) filter.val
          else
            compareVersions' filter.op (getVar (head filter.val))
            (getVar (head (tail filter.val)))
        else if filter ? id then
          getVar filter
        else
          throw "Couldn't understand package filter: ${toJSON filter}";
      collectAcceptableVerisions = v:
        let
          a = elemAt v.val 0;
          b = elemAt v.val 1;
          a' = collectAcceptableVerisions a;
          b' = collectAcceptableVerisions b;
        in if v ? op then
          if v.op == "or" then
            if a' != [ ] then a' else if b' != [ ] then b' else [ ]
          else if v.op == "and" then
            if a' != [ ] && b' != [ ] then a' ++ b' else [ ]
          else
            throw "Not a logop: ${v.op}"
        else if v ? options then
          if all' (checkPackageFilter v.val) v.options then [ v ] else [ ]
        else if isString v then
          [ v ]
        else if isList v then
          concatMap collectAcceptableVerisions v
        else
          throw "Couldn't understand a part filtered package list: ${toJSON v}";

    in collectAcceptableVerisions;

  pkgVarsFor = name: lib.mapAttrs' (var: nameValuePair "${name}:${var}");

  setVars = vars:
    let
      v = attrValues (mapAttrs (name: value: ''
        export ${opamVarToShellVar name}="''${${opamVarToShellVar name}-${
          toJSON value
        }}"
      '') vars);
    in concatStringsSep "" v;

  setEnv = env:
    concatMapStringsSep ""
    (concatMapStringsSep "\n" ({ op, val }: envOpToBash op val))
    (normalize' env);

  evalFilter = level: val:
    let
      listElemSeparator = if level == 0 then
        "; "
      else if level == 1 then
        " "
      else
        throw "Level too big: ${toString level}";

      quoteCommandPart = part:
        if level == 1 then
          if part.type == "command" then
            toShellString part
          else
            ''"${toShellString part}"''
        else
          part.value;
    in if val ? id then {
      type = "string";
      value = "$" + opamVarToShellVar val.id;
    } else if val ? op then {
      type = "condition";
      value = opToBash val.op (map (x:
        if isList x then
          head (map (evalFilter level) x)
        else
          evalFilter level x) val.val);
    } else if isList val then { # FIXME EWWWWWW
      type = "command";
      value = concatMapStringsSep listElemSeparator
        (part: quoteCommandPart (evalFilter (level + 1) part)) val;
    } else if val ? options then {
      type = "command";
      value = "if ${
          concatMapStringsSep " && " (x: toCondition (evalFilter level x))
          val.options
        }; then ${toCommand (evalFilter level val.val)}; fi";
    } else {
      type = "string";
      value = interpretStringsRec val;
    };

  evalSection = section: let s = evalFilter 0 (normalize section); in s.value;

  # FIXME do this for every section
  normalize = section:
    if !isList (val section) then
      [ [ section ] ]
    else if (val section) == [ ] || !isList (val (head (val section))) then
      [ section ]
    else
      section;

  # FIXME do this for every section
  normalize' = section:
    if !isList section then
      [ [ section ] ]
    else if section == [ ] || !isList (head section) then
      [ section ]
    else
      section;

  interpretStringsRec = val:
    if isString val then
      interpretStringInterpolation val
    else if isList val then
      map interpretStringsRec val
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
  interpretStringInterpolation = s:
    let
      pieces = filter isString (split "([%][{]|[}][%])" s);
      result = foldl' ({ i, result }:
        piece: {
          i = !i;
          result = result + (if i then
            toShellString (evalFilter 2 { id = piece; })
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
