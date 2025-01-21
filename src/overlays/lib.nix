lib: {
  applyOverrides =
    super: overrides:
    builtins.removeAttrs (lib.mapAttrs' (
      name: f: lib.nameValuePair (if super ? ${name} then name else "") (super.${name}.overrideAttrs f)
    ) overrides) [ "" ];
}
