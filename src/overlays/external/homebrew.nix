pkgs:
with pkgs;
# Map from homebrew package names to nixpkgs packages.
# To add a new package:
# 1. Find the package in nixpkgs:
#   * Use https://search.nixos.org/packages or `nix search` to find the package by name or description;
#   * Use https://mynixos.com/ or `nix-index`/`nix-locate` to find the package by files contained therein;
# 2. If some changes to the package are needed to be compatible with the homebrew one, make an override in the let binding below;
# 3. Add it to the list. Keep the quotation marks around the homebrew package name, even if not needed, and sort the list afterwrads.
let
  rust' = buildEnv {
    name = "rust-and-cargo";
    paths = [
      rustc
      cargo
      libiconv
    ];
  };

  pkgconf' = pkgs.pkgconf.overrideAttrs (oa: {
    installPhase = oa.installPhase + ''
      ln -s $out/bin/pkgconf $out/bin/pkg-config
    '';
  });

in
# Please keep this list sorted alphabetically and one-line-per-package
pkgs
// {
  "autoconf" = pkgsBuildBuild.autoconf;
  "cairo" = cairo.dev;
  "expat" = expat.dev;
  "gmp" = gmp.dev;
  "gtk+3" = gtk3.dev;
  "gtksourceview3" = gtksourceview3.dev;
  "libxml2" = libxml2.dev;
  "libpq" = postgresql;
  "pkgconf" = pkgconf';
  "postgresql" = postgresql;
  "postgresql@14" = postgresql_14;
  "postgresql@15" = postgresql_15;
  "postgresql@16" = postgresql_16;
  "proctools" = procps;
  "python@3" = python3;
  "python@3.8" = python38;
  "python@3.9" = python39;
  "python@3.10" = python310;
  "python@3.12" = python312;
  "python@3.13" = python313;
  "rust" = rust';
  "zlib" = zlib.dev;
}
