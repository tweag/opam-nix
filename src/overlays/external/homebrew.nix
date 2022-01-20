# Map from homebrew to nixpkgs
pkgs:
with pkgs;
let

  # Please keep this list sorted alphabetically and one-line-per-package
in {
  "autoconf" = pkgsBuildBuild.autoconf;
  "cairo" = cairo.dev;
  "expat" = expat.dev;
  "gmp" = gmp.dev;
  "gnupg" = gnupg;
  "gtk+3" = gtk3.dev;
  "gtksourceview3" = gtksourceview3.dev;
  "libev" = libev;
  "libffi" = libffi;
  "libxml2" = libxml2.dev;
  "openssl" = openssl;
  "pkg-config" = pkg-config;
  "postgresql" = postgresql;
  "proctools" = procps;
  "zlib" = zlib.dev;
}
