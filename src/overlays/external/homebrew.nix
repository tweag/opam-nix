# Map from homebrew to nixpkgs
pkgs:
with pkgs;
let

  # Please keep this list sorted alphabetically and one-line-per-package
in pkgs // {
  "autoconf" = pkgsBuildBuild.autoconf;
  "cairo" = cairo.dev;
  "expat" = expat.dev;
  "gmp" = gmp.dev;
  "gtk+3" = gtk3.dev;
  "gtksourceview3" = gtksourceview3.dev;
  "libxml2" = libxml2.dev;
  "proctools" = procps;
  "zlib" = zlib.dev;
}
