# Map from homebrew to nixpkgs
pkgs:
with pkgs;
let

in {
  "autoconf" = pkgsBuildBuild.autoconf;
  "cairo" = cairo.dev;
  "expat" = expat.dev;
  "gnupg" = gnupg;
  "gmp" = gmp.dev;
  "gtk+3" = gtk3.dev;
  "gtksourceview3" = gtksourceview3.dev;
  "libxml2" = libxml2.dev;
  "pkg-config" = pkg-config;
  "zlib" = zlib.dev;
}
