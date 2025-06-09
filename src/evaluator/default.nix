lib:
let
  inherit (builtins)
    elemAt
    replaceStrings
    head
    isString
    isList
    toJSON
    tail
    listToAttrs
    length
    attrValues
    mapAttrs
    concatStringsSep
    isBool
    isInt
    filter
    split
    foldl'
    match
    fromJSON
    nixVersion
    throw
    ;
  inherit (lib)
    splitString
    concatMap
    nameValuePair
    concatMapStringsSep
    all
    any
    zipListsWith
    optionalAttrs
    optional
    escapeShellArg
    hasInfix
    stringToCharacters
    flatten
    last
    warn
    path
    ;

  inherit (import ../lib.nix lib) md5sri;

  isImpure = builtins ? currentSystem;
in
rec {
  # Note: if you are using this evaluator directly, don't forget to source the setup
  setup = ./setup.sh;

  /**
    Compare two characters, `a` and `b`.

    Returns 0 if `a == b`,
    Otherwise returns 1 if `a > b` and -1 if `a < b`;
    However, it considers `~` to be less than any other character.
  */
  chrcmp =
    a: b:
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

  /**
    Compare two strings lexicographically, considering `~` to be less than any other character, including end of sequence.
    This is simple but slow, use `lexiCompare` instead.
  */
  strcmp =
    a: b:
    let
      a' = stringToCharacters a ++ [ "" ];
      b' = stringToCharacters b ++ [ "" ];
    in
    head (filter (x: x != 0) (zipListsWith chrcmp a' b'));

  /**
    Compare two strings lexicographically, considering `~` to be less than any other character.

    # Arguments

    `a` and `b`, strings to be compared.

    # Returns
    Returns 0 if `a == b`,
    Otherwise returns 1 if `a > b` and -1 if `a < b`;
    However, it considers `~` to be greater than any other character, including end of sequence.

    # Examples

    ```nix
    lexiCompare "1.2.3" "1.2.3" == 0 # a == b
    ```

    ```nix
    lexiCompare "1.2.2" "1.2.3" == -1 # a < b
    ```

    ```nix
    lexiCompare "a~" "a" == -1 # a < b
    ```

    ```nix
    lexiCompare "1.0" "1.0~beta" == 1 # a > b
    ```
  */
  lexiCompare =
    a: b:
    if a == b then
      0
    else if isString a && (hasInfix "~" a || hasInfix "~" b) then
      strcmp a b
    else if a > b then
      1
    else
      (-1);

  /**
    Trim all zeroes from the start of the (numeric) string.

    # Examples

    ```nix
    trimZeroes "000123" == "123"
    ```
  */
  trimZeroes = s: head (match ("[0]*([0-9]+)") s);

  /**
    Compare two versions using opam's version comparison semantics.

    # Arguments

    - `op` - the comparison operation; one of `eq`, `lt`, `gt`, `leq`, `geq`.
    - `a` and `b` - the versions to be compared.

    # Examples

    ```nix
    compareVersions' "eq" "0.1.2" "0.1.2" == true
    ```

    ```nix
    compareVersions' "geq" "0.1.2" "0.1.2" == true
    ```

    ```nix
    compareVersions' "gt" "0.1.2" "0.1.1" == false
    ```

    ```nix
    compareVersions' "gt" "0.1.2~beta" "0.1.2" == true
    ```
  */
  compareVersions' =
    op: a: b:
    let
      prepareVersion =
        version: map (x: if isList x then fromJSON (trimZeroes (head x)) else x) (split "([0-9]+)" version);
      comp' = filter (x: x != 0) (zipListsWith lexiCompare (prepareVersion a) (prepareVersion b));
      comp = if comp' == [ ] then 0 else head comp';
    in
    if isNull a || isNull b then
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

  /**
    Like `lib.any`, but handle `pred` returning `null`
  */
  any' = pred: any (x: !isNull (pred x) && pred x);
  /**
    Like `lib.all`, but handle `pred` returning `null`
  */
  all' = pred: all (x: !isNull (pred x) && pred x);

  /**
    Recursively collects **all** values from opam's "option list" (list of options) into a Nix list.
    This includes recursively going through sub-lists, operator arguments, and sub-groups.
    This ignores any `conditions` on the option list.

    See also: https://opam.ocaml.org/doc/Manual.html#General-syntax

    # Example

    ```nix
    collectAllValuesFromOptionList [
      {
        val = "foo";
        conditions = [ { prefix_relop = "eq"; "arg" = "1.0"; } ];
      }
      {
        group = [
          {
            logop = "or";
            lhs = "bar";
            rhs = "baz";
          }
          "goo"
        ];
      }
    ]
    == [ "foo" "bar" "baz" "goo" ]
    ```
  */
  collectAllValuesFromOptionList =
    v:
    if isString v then
      [ v ]
    else if v ? conditions then
      collectAllValuesFromOptionList v.val
    else if v ? logop then
      collectAllValuesFromOptionList v.lhs ++ collectAllValuesFromOptionList v.rhs
    else if isList v then
      concatMap collectAllValuesFromOptionList v
    else if v ? group then
      concatMap collectAllValuesFromOptionList v.group
    else
      throw "unexpected dependency: ${toJSON v}";

  /**
    Get all possible dependencies (both `depends` and `depopts`) of a package, including conflicting ones.
  */
  functionArgsFor =
    pkgdef:
    let
      # Get _all_ dependencies mentioned in the opam file

      allDepends = collectAllValuesFromOptionList pkgdef.depends or [ ];
      allDepopts = collectAllValuesFromOptionList pkgdef.depopts or [ ];

      genArgs = deps: optional: listToAttrs (map (name: nameValuePair name optional) deps);
    in
    genArgs allDepends false // genArgs allDepopts true;

  /**
    Produce a bash expression which evaluates an opam environment update operator.

    See also: https://opam.ocaml.org/doc/Manual.html#Environment-updates

    Supported operators are:
    - `set` (`=`)
    - `prepend` (`+=`)
    - `prepend_trailing` (`:=`)
    - `append` (`=+`)
    - `append_trailing` (`=:`)
  */
  envOpToShell =
    v@{ lhs, rhs, ... }:
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

  /**
    Given an opam variable name, rewrite such that it can be used as a bash variable name, prepending `opam__`.

    # Example

    ```nix
    varToShellVar "conf-g++:installed" == "opam__conf_g____installed"
    ```
  */
  varToShellVar =
    var:
    let
      s = splitString ":" var;
    in
    concatMapStringsSep "__" (replaceStrings [ "-" "+" "." ] [ "_" "_" "_" ]) ([ "opam" ] ++ s);

  /**
    Turn an evaluator expression into a bash string.

    An evaluator expression is `{ type = <...>; value = <...>; }`, where:
    - if `type` is `string`, `value` is a string;
    - if `type` is `command`, `value` is a shell command to be executed which prints the desired result to stdout;
    - if `type` is `optional`, `value` is a list of two elements:
      1. A condition (shell command whose return status determines whether to return anything)
      2. A command (shell command which prints the desired output to stdout)
  */
  toShellString =
    { type, value }:
    if type == "string" then
      value
    else if type == "command" then
      "$(${value})"
    else if type == "optional" then
      ''$(if ${elemAt value 0}; then ${elemAt value 1}; fi)''
    else
      throw "Can't convert ${type} to shell string";
  /**
    Turn an evaluator expression into a bash expression producing a string to `stdout`.

    An evaluator expression is `{ type = <...>; value = <...>; }`, where:
    - if `type` is `string`, `value` is a string;
    - if `type` is `command`, `value` is a shell command to be executed which prints the desired result to stdout;
    - if `type` is `optional`, `value` is a list of two elements:
      1. A condition (shell command whose return status determines whether to return anything)
      2. A command (shell command which prints the desired output to stdout)
  */
  toCommand =
    { type, value }:
    if type == "command" then
      value
    else if type == "string" then
      ''echo "${value}"''
    else if type == "optional" then
      ''if ${elemAt value 0}; then ${elemAt value 1}; fi''
    else
      throw "Can't convert ${type} to command";
  /**
    Turn an evaluator expression into a bash expression producing the evaluation result as an exit code.

    An evaluator expression is `{ type = <...>; value = <...>; }`, where:
    - if `type` is `string`, `value` is a string;
    - if `type` is `command`, `value` is a shell command to be executed which prints the desired result to stdout;
    - if `type` is `optional`, `value` is a list of two elements:
      1. A condition (shell command whose return status determines whether to return anything)
      2. A command (shell command which prints the desired output to stdout)
  */
  toCondition =
    { type, value }@x: if type == "condition" then value else ''[[ "${toShellString x}" == true ]]'';

  /**
    Turn an evaluator expression into a bash expression, adding the result of the expression to an `args` bash array.

    An evaluator expression is `{ type = <...>; value = <...>; }`, where:
    - if `type` is `string`, `value` is a string;
    - if `type` is `command`, `value` is a shell command to be executed which prints the desired result to stdout;
    - if `type` is `optional`, `value` is a list of two elements:
      1. A condition (shell command whose return status determines whether to return anything)
      2. A command (shell command which prints the desired output to stdout)

    This function is used to evaluate argument lists of commands, e.g. given an
    opam list like `[["make"] ["make" "test" {with-test}]]` the evaluator will use this function to produce

    ```bash
      args+=("make")
      "${args[@]}"
      args+=("make")
      if [[ "$opam__with__test" == true ]]; then args+=("$(echo "test")"); fi
      "${args[@]}"
    ```

    The reason we can't use bash to parse and pass arguments is that it is
    impossible to both prevent shell expansion and have optional arguments:

    ```bash
    make $(if <condition> then <command> fi)
    ```

    Will break if `<command>` produces output with spaces in it (eg. `foo bar`),
    as it will result in two arguments passed to `make`: `make foo bar`; and

    ```bash
    make "$(if <condition> then <command> fi)"
    ```

    Will break if `<condition>` is false and nothing is produced, calling `make ""`
    (with an empty argument instead of no argument).
  */
  toCommandArg =
    { type, value }:
    if type == "string" then
      ''args+=("${value}")''
    else if type == "command" then
      ''args+=("$(${value})")''
    else if type == "optional" then
      ''if ${elemAt value 0}; then args+=("$(${elemAt value 1})"); fi''
    else
      throw "Can't convert ${type} to command arg";

  /**
    Given an attrset of variables and their values, evaluate a package formula, taking into consideration all `condition`s.

    This is used to evaluate the actually needed dependencies of an opam package.

    # Example

    ```nix
    filterPackageFormula { dep1 = "0.1"; dep2 = "0.1"; with-doc = true; with-test = false; } [
      { val = "dep1"; conditions = [ { id = "with-doc"; } ]; }
      { val = "dep2"; conditions = [ { id = "with-test"; } ]; }
    ]
    == [ "dep1" ]
    ```
  */
  filterPackageFormula =
    vars:
    let
      getVar = id: lib.attrByPath (splitString ":" id) null vars;

      getVersion =
        x:
        if x ? id then
          getVar x.id
        else if isString x then
          x
        else
          throw "Not a valid version description: ${toJSON x}";

      toString' =
        value:
        if value == true then
          "true"
        else if value == false then
          "false"
        else
          toString value;

      checkVersionFormula =
        pkg: filter:
        if filter ? pfxop then
          if filter.pfxop == "not" then
            let
              r = checkVersionFormula pkg filter.arg;
            in
            if isNull r then null else !r
          else if filter.pfxop == "defined" then
            vars ? filter.arg.id
          else
            throw "Unknown pfxop ${filter.pfxop}"
        else if filter ? logop then
          if filter.logop == "and" then
            all' (checkVersionFormula pkg) [
              filter.lhs
              filter.rhs
            ]
          else if filter.logop == "or" then
            any' (checkVersionFormula pkg) [
              filter.lhs
              filter.rhs
            ]
          else
            throw "Unknown logop ${filter.logop}"
        else if filter ? prefix_relop then
          compareVersions' filter.prefix_relop (getVar pkg) (getVersion filter.arg)
        else if filter ? relop then
          compareVersions' filter.relop (toString' (getVersion filter.lhs)) (
            toString' (getVersion filter.rhs)
          )
        else if filter ? id then
          getVar filter.id
        else if isList filter then
          all' (checkVersionFormula pkg) filter
        else if filter ? group then
          all' (checkVersionFormula pkg) filter.group
        else
          throw "Couldn't understand package condition: ${toJSON filter}";

      filterPackageFormulaRec =
        v:
        let
          lhs' = filterPackageFormulaRec v.lhs;
          rhs' = filterPackageFormulaRec v.rhs;
        in
        if v ? logop then
          if v.logop == "or" then
            if lhs' != [ ] then
              lhs'
            else if rhs' != [ ] then
              rhs'
            else
              [ ]
          else if v.logop == "and" then
            if lhs' != [ ] && rhs' != [ ] then
              flatten [
                lhs'
                rhs'
              ]
            else
              [ ]
          else
            throw "Unknown logop ${v.logop}"
        else if v ? conditions then
          if all' (checkVersionFormula v.val) v.conditions then filterPackageFormulaRec v.val else [ ]
        else if isString v then
          if !isNull (getVar v) then v else [ ]
        else if isList v then
          map filterPackageFormulaRec v
        else if v ? group then
          flatten (map filterPackageFormulaRec v.group)
        else
          throw "Couldn't understand a part of filtered list: ${toJSON v}";
    in
    v: flatten (filterPackageFormulaRec v);


  /**
    Given an attrset of variables and their values, evaluate an option list, taking into consideration all `condition`s.

    Similar to `filterPackageFormula`.

    This is used to evaluate the patches, substs and messages of an opam package.
  */
  filterOptionList =
    vars:
    let
      getVar = id: lib.attrByPath (splitString ":" id) null vars;

      getVersion =
        x:
        if x ? id then
          getVar x.id
        else if isString x then
          x
        else
          throw "Not a valid version description: ${toJSON x}";

      checkVersionFormula =
        pkg: filter:
        if filter ? pfxop then
          if filter.pfxop == "not" then
            let
              r = checkVersionFormula pkg filter.arg;
            in
            if isNull r then null else !r
          else if filter.pfxop == "defined" then
            vars ? filter.arg.id
          else
            throw "Unknown pfxop ${filter.pfxop}"
        else if filter ? logop then
          if filter.logop == "and" then
            all' (checkVersionFormula pkg) [
              filter.lhs
              filter.rhs
            ]
          else if filter.logop == "or" then
            any' (checkVersionFormula pkg) [
              filter.lhs
              filter.rhs
            ]
          else
            throw "Unknown logop ${filter.logop}"
        else if filter ? relop then
          compareVersions' filter.relop (getVersion filter.lhs) (getVersion filter.rhs)
        else if filter ? id then
          getVar filter.id
        else if isList filter then
          all' (checkVersionFormula pkg) filter
        else if filter ? group then
          all' (checkVersionFormula pkg) filter.group
        else
          throw "Couldn't understand option list condition: ${toJSON filter}";

      filterOptionListRec =
        v:
        if v ? conditions then
          if all' (checkVersionFormula v.val) v.conditions then filterOptionListRec v.val else [ ]
        else if isString v then
          v
        else if isList v then
          map filterOptionListRec v
        else if v ? group then
          flatten (map filterOptionListRec v.group)
        else
          throw "Couldn't understand a part of filtered list: ${toJSON v}";
    in
    v: flatten (filterOptionListRec v);

  pkgVarsFor = name: lib.mapAttrs' (var: nameValuePair "${name}:${var}");

  /**
    Turn an attrset of variables into a bash expression setting them (but not overriding if set already)

    # Example

    ```nix
    varsToShell { "foo" = "bar"; "g++" = "1.2.3"; }
    == ''
      foo="''${foo-"bar"}"
      g__="''${g__-"1.2.3"}"
    ''
    ```
  */
  varsToShell =
    vars:
    let
      v = attrValues (
        mapAttrs (name: value: ''
          ${varToShellVar name}="''${${varToShellVar name}-${toJSON value}}"
        '') vars
      );
    in
    concatStringsSep "" v;

  /**
    Turn a list of opam's "environment updates" into a bash expression modifying them

    See also: https://opam.ocaml.org/doc/Manual.html#Environment-updates

    # Example

    ```nix
    envToShell [ { env_update = "append"; lhs.id = "foo"; rhs = "bar"; } ]
    == ''
      foo="''${foo-}''${foo+:}bar"
    ''
    ```
  */
  envToShell =
    env: concatMapStringsSep "\n" envOpToShell (flatten (if isList env then env else [ env ]));

  /**
    Given an opam list, produce a bash expression evaluating it.

    Opam variables (e.g. package versions) are taken from corresponding bash variables at runtime.

    This is used to evaluate the commands needed to build and install a package, and to interpolate strings.

    # Arguments

    1. `level`: the level of nested list. This is needed because of how we
        evaluate build commands (see `toCommandArg`). The topmost section is level 0,
        commands are level 1, command arguments are level 2.
    2. `val`: the opam list to be evaluated.
  */
  filterOptionListInShell =
    level: val:
    if val ? id then
      let
        s = splitString ":" val.id;
        pkgs = splitString "+" (head s);
        isEnable = last s == "enable";
        trueish = if isEnable then "enable" else "true";
        falseish = if isEnable then "disable" else "false";
      in
      {
        type = "string";
        value =
          if length pkgs == 1 then
            "\${${varToShellVar val.id}}"
          else
            "$(if ${
              concatMapStringsSep " && " (
                pkg: "[[ \${${varToShellVar (concatStringsSep ":" ([ pkg ] ++ tail s))}} == ${trueish} ]]"
              ) pkgs
            }; then echo ${trueish}; else echo ${falseish}; fi)";
      }
    else if val ? relop || val ? logop then
      {
        type = "condition";
        value =
          let
            op = val.relop or val.logop;
            lhsS = toShellString (filterOptionListInShell level val.lhs);
            rhsS = toShellString (filterOptionListInShell level val.rhs);
            lhsC = toCondition (filterOptionListInShell level val.lhs);
            rhsC = toCondition (filterOptionListInShell level val.rhs);
          in
          if op == "eq" then
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
      }
    else if val ? pfxop then
      {
        type = "condition";
        value =
          if val.pfxop == "not" then
            "! ${toCondition (filterOptionListInShell level val.arg)}"
          # else if val.pfxop == "defined" then
          #   "[[ -n ${val.arg.} ]]"
          else
            throw "Unknown pfxop ${val.pfxop}";
      }
    else if val == [ ] then
      {
        type = "command";
        value = ":";
      }
    else if isList val then
      {
        # Build the argument list as an array to properly remove arguments
        # disabled by a condition. [toCommandArg] implements the convention.
        type = "command";
        value =
          if level == 1 then
            ''
              args=()
              ${concatMapStringsSep "\n" (part: toCommandArg (filterOptionListInShell (level + 1) part)) val}
              "''${args[@]}"''
          else if level == 0 then
            concatMapStringsSep "\n" (part: toCommand (filterOptionListInShell (level + 1) part)) val
          else
            throw "Level too big";
      }
    else if val ? conditions then
      {
        type = "optional";
        value = [
          (concatMapStringsSep " && " (x: toCondition (filterOptionListInShell level x)) val.conditions)
          (toCommand (filterOptionListInShell level val.val))
        ];
      }
    else if isString val then
      {
        type = "string";
        value = interpolateStringsRec val;
      }
    else if val ? group then
      filterOptionListInShell level (head val.group)
    else
      throw "Can't convert ${toJSON val} to shell commands";

  /**
    Given an opam file section, produce a bash expression that evaluates it.

    Opam variables (e.g. package versions) are taken from corresponding bash variables at runtime.

    This is used to evaluate the commands needed to build and install a package.
  */
  filterSectionInShell =
    section:
    let
      val = x: x.val or x;
      normalize =
        section:
        if !isList (val section) then
          [ [ section ] ]
        else if (val section) == [ ] || !isList (val (head (val section))) then
          [ section ]
        else
          section;
      s = filterOptionListInShell 0 (normalize section);
    in
    toCommand s;

  /**
    Recursively interpolate all strings in an opam expression.
  */
  interpolateStringsRec =
    val:
    if isString val then
      interpolateString val
    else if isList val then
      map interpolateStringsRec val
    else if isBool val || isInt val then
      toString' val
    else
      val;

  /**
    Map (some) Nix values to strings which make sense in an opam context.
  */
  toString' =
    v:
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
  /**
    Given an opam string, produce a bash string that would interpolate it when evaluated.

    # Example

    ```nix
    interpolateString "This is a string. Here is the value of foo: %{foo}%"
    == "This is a string. Here is the value of foo: ''${opam__foo}"
    ```
  */
  interpolateString =
    s:
    let
      pieces = filter isString (split "([%][{]|[}][%])" s);
      result =
        foldl'
          (
            { i, result }:
            piece: {
              i = !i;
              result = result + (if i then toShellString (filterOptionListInShell 2 { id = piece; }) else piece);
            }
          )
          {
            i = false;
            result = "";
          }
          pieces;
    in
    if length pieces == 1 then s else result.result;

  /**
    Check if a hash is of a certain hashing method.
    - If it is, return an attribute set with a single attribute: name will be the method, and the hash will be the value
    - Otherwise, return `{}`

    # Examples

    ```nix
    tryHash "sha256" "sha256=48554abfd530fcdaa08f23f801b699e4f74c320ddf7d0bd56b0e8c24e55fc911"
    == { sha256 = "48554abfd530fcdaa08f23f801b699e4f74c320ddf7d0bd56b0e8c24e55fc911"; }
    ```

    ```nix
    tryHash "md5" "sha256=48554abfd530fcdaa08f23f801b699e4f74c320ddf7d0bd56b0e8c24e55fc911"
    == { }
    ```
  */
  tryHash =
    method: c:

    let
      m = match "${method}=(.*)" c;
    in
    optional (!isNull m) { ${method} = head m; };

  /**
    Similar to `tryHash`, but specifically for `md5`.

    md5 is special in two ways:
    - nixpkgs only accepts it as an SRI,
    - and checksums without an explicit algo are assumed to be md5 in opam.

    # Examples

    ```nix
    trymd5 "sha256=48554abfd530fcdaa08f23f801b699e4f74c320ddf7d0bd56b0e8c24e55fc911"
    == { }
    ```

    ```nix
    trymd5 "md5=3e969b841df1f51ca448e6e6295cb451"
    == { hash = "md5-PpabhB3x9RykSObmKVy0UQ=="; }
    ```

    ```nix
    trymd5 "3e969b841df1f51ca448e6e6295cb451"
    == { hash = "md5-PpabhB3x9RykSObmKVy0UQ=="; }
    ```
  */
  trymd5 =
    c:
    let
      m = match "md5=(.*)" c;
      m' = match "([0-9a-f]{32})" c;
      success = md5: [ { hash = md5sri (head md5); } ];
    in
    if !isNull m then
      success m
    else if !isNull m' then
      success m'
    else
      [ ];

  /**
    Given a list of opam checksums, get the "best" hash to use, in a format ready to be passed to `fetchurl` and friends.

    # Examples

    ```nix
    getHashes [ "md5=3e969b841df1f51ca448e6e6295cb451" "sha256=48554abfd530fcdaa08f23f801b699e4f74c320ddf7d0bd56b0e8c24e55fc911" ]
    == { sha256 = "48554abfd530fcdaa08f23f801b699e4f74c320ddf7d0bd56b0e8c24e55fc911"; }
    ```
  */
  getHashes =
    checksums:
    head (concatMap (x: tryHash "sha512" x ++ tryHash "sha256" x ++ trymd5 x) checksums ++ [ { } ]);

  /**
    Parse a URL as in RFC3986.

    # Example

    ```nix
    parseUrl "https://github.com/ocaml/ocaml/archive/5.2.0.tar.gz"
    == {
      authority = "github.com";
      fragment = null;
      path = "/ocaml/ocaml/archive/5.2.0.tar.gz";
      proto = "https";
      query = null;
      scheme = "https";
      transport = null;
    }
    ```
  */
  parseUrl =
    url:
    let
      # Modified from https://www.rfc-editor.org/rfc/rfc3986#appendix-B
      m = match "^((([^:/?#+]+)[+]?([^:/?#]+)?):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?" url;
    in
    {
      scheme = elemAt m 1;
      proto = elemAt m 2;
      transport = elemAt m 3;
      authority = elemAt m 5;
      path = elemAt m 6;
      query = elemAt m 8;
      fragment = elemAt m 10;
    };

  /**
    Given a git url (in an attribute form, as returned by `parseUrl`), fetch it and return the path.

    If the URL fragment is not a commit sha1, impure evaluation mode is required (as the target commit may change).
  */
  fetchGitURL =
    url:
    let
      isRev = s: !isNull (match "[0-9a-f]{40}" s);
      hasRev = (!isNull url.fragment) && isRev url.fragment;
      optionalRev = optionalAttrs hasRev { rev = url.fragment; };
      refsOrWarn =
        if (!isNull url.fragment) && !hasRev then
          {
            ref = url.fragment;
          }
        else if lib.versionAtLeast nixVersion "2.4" then
          {
            allRefs = true;
          }
        else
          warn
            "[opam-nix] Nix version is too old for allRefs = true; fetching a repository may fail if the commit is on a non-master branch"
            { };
      gitUrl =
        with url;
        (if isNull transport then "" else "${transport}://")
        + authority
        + url.path
        + (if isNull query then "" else "?${query}");
      path =
        (builtins.fetchGit (
          {
            url = gitUrl;
            submodules = true;
          }
          // refsOrWarn
          // optionalRev
        ))
        // {
          url = gitUrl;
        };
    in
    if !hasRev && !isImpure then
      throw "[opam-nix] a git dependency without an explicit sha1 is not supported in pure evaluation mode; try with --impure"
    else
      path;

  /**
    Given a URL (as a string) and a project root, return the path to the URL target (fetching it if necessary).
  */
  fetchWithoutChecksum =
    url: project:
    let
      u = parseUrl url;
    in
    # git://git@domain:path/to/repo is interpreted as ssh, hence drop the git://
    if u.proto == "git" then
      fetchGitURL u
    else if u.scheme == "http" || u.scheme == "https" then
      builtins.fetchTarball url
    # if no protocol assume a local file path
    else if
      u.scheme == null
      &&
        # absolute path
        !path.subpath.isValid url
    then
      /. + url
    else if u.scheme == null && project != null then
      # relative path (note '..' is not accepted)
      path.append project url
    else
      throw "[opam-nix] URL scheme '${u.scheme}' is not yet supported";

  /**
    Given a nixpkgs and a opam package definition, return a path to the package source, fetching it if necessary.

    Nix impure evaluation mode may be required if the `checksum` is missing,
    there's no git commit sha1, and the package source is not a local file.
  */
  getUrl =
    pkgs: pkgdef:
    let
      hashes =
        if pkgdef.url.section ? checksum then
          if isList pkgdef.url.section.checksum then
            getHashes pkgdef.url.section.checksum
          else
            getHashes [ pkgdef.url.section.checksum ]
        else
          { };
      archive = pkgdef.url.section.src or pkgdef.url.section.archive or "";
      mirrors =
        let
          m = pkgdef.url.section.mirrors or [ ];
        in
        if isList m then m else [ m ];
      src =
        if pkgdef ? url then
          # Default unpacker doesn't support .zip
          if hashes == { } then
            fetchWithoutChecksum archive null
          else
            pkgs.fetchurl ({ urls = [ archive ] ++ mirrors; } // hashes)
        else
          pkgdef.src or pkgs.pkgsBuildBuild.emptyDirectory;
    in
    {
      inherit archive src;
    };

}
