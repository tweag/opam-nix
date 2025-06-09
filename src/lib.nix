lib:

let
  inherit (lib)
    stringToCharacters
    drop
    converge
    filterAttrsRecursive
    nameValuePair
    ;
  inherit (builtins)
    elemAt
    length
    listToAttrs
    ;

in
rec {
  base16digits = rec {
    "0" = 0;
    "1" = 1;
    "2" = 2;
    "3" = 3;
    "4" = 4;
    "5" = 5;
    "6" = 6;
    "7" = 7;
    "8" = 8;
    "9" = 9;
    "a" = 10;
    "b" = 11;
    "c" = 12;
    "d" = 13;
    "e" = 14;
    "f" = 15;
    A = a;
    B = b;
    C = c;
    D = d;
    E = e;
    F = f;
  };

  base64digits = stringToCharacters "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

  mod = a: b: a - (a / b) * b;

  /**
    Convert a base16 number into base64
  */
  base16tobase64 =
    s:
    let
      chars = stringToCharacters s;
      go =
        x:
        let
          get16 = n: base16digits.${elemAt x n};
          a = get16 2;
          b = (get16 1) * 16;
          c = (get16 0) * 256;
          sum =
            if length x > 2 then
              c + b + a
            else if length x == 2 then
              c + b
            else if length x == 1 then
              c
            else
              0;
          get = elemAt base64digits;
          value = get (sum / 64) + get (mod sum 64);
        in
        (if length x > 0 then value else "") + (if length x > 2 then go (drop 3 x) else "");
    in
    go chars;

  /**
    Produce an SRI of a given md5 hash (in base16 format)
  */
  md5sri = md5: "md5-${base16tobase64 md5}==";

  /**
    Recursively remove all empty attributes from an attribute set

    # Example

    ```nix
    filterOutEmpty { a = 10; b = { c = { }; }; }
      == { a = 10; }
    ```
  */
  filterOutEmpty = converge (filterAttrsRecursive (_: v: v != { }));


  /**
    Given a list, produce an attribute set with attribute names taken from `by` sub-attribute in each element.
    The `${by}` sub-attribute is kept intact in the new attribute set.

    # Arguments

    1. `by`: which sub-attribute to take the attribute name from
    2. `list`: the list to convert

    # Example

    ```nix
    listToAttrsBy "surname" [ { name = "Alice"; surname = "Smith"; } { name = "Bob"; surname = "Jones"; } ]
      == { Smith = { name = "Alice"; surname = "Smith"; }; Jones = { name = "Bob"; surname = "Jones"; }; }
    ```
  */
  listToAttrsBy = by: list: listToAttrs (map (x: nameValuePair x.${by} x) list);
}
