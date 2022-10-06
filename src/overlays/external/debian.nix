pkgs:
with pkgs;
# Map from debian package names to nixpkgs packages.
# To add a new package:
# 1. Find the package in nixpkgs:
#   * Use https://search.nixos.org/packages or `nix search` to find the package by name or description;
#   * Use https://mynixos.com/ or `nix-index`/`nix-locate` to find the package by files contained therein;
# 2. If some changes to the package are needed to be compatible with the debian one, make an override in the let binding below;
# 3. Add it to the list. Keep the quotation marks around the debian package name, even if not needed, and sort the list afterwrads.
let
  hidapi' = hidapi.overrideAttrs (_: {
    postInstall = ''
      mv $out/include/hidapi/* $out/include
      rm -d $out/include/hidapi
      ln -s $out/lib/libhidapi-hidraw.la $out/lib/libhidapi.la
      ln -s $out/lib/libhidapi-hidraw.so.0.0.0 $out/lib/libhidapi.so
    '';
  });

  cargo' = buildEnv {
    name = "cargo";
    paths = [ pkgsBuildBuild.cargo pkgsBuildHost.rustc ];
  };

  gtksourceview' = buildEnv {
    name = "gtk-bunch";
    paths = [
      gnome2.gtksourceview
      gnome2.gtk.dev
      pango.dev
      glib.dev
      harfbuzz.dev
      cairo.dev
      gdk-pixbuf.dev
      atk.dev
      freetype.dev
      fontconfig.dev
    ];
  };
  # Please keep this list sorted alphabetically and one-line-per-package
in pkgs // {
  "autoconf" = pkgsBuildBuild.autoconf;
  "cargo" = cargo';
  "debianutils" = which; # eurgh
  "g++" = pkgsBuildHost.gcc;
  "jq" = pkgsBuildBuild.jq;
  "libbluetooth-dev" = bluez5;
  "libcairo2-dev" = cairo.dev;
  "libcapnp-dev" = capnproto;
  "libcurl4-gnutls-dev" = curl.dev;
  "libev-dev" = libev;
  "libexpat1-dev" = expat.dev;
  "libffi-dev" = libffi.dev;
  "libglib2.0-dev" = glib.dev;
  "libgmp-dev" = gmp.dev;
  "libgnomecanvas2-dev" = gnome2.libgnomecanvas.dev;
  "libgtk2.0-dev" = gtk2.dev;
  "libgtk-3-dev" = gtk3.dev;
  "libgtksourceview2.0-dev" = gtksourceview';
  "libgtksourceview-3.0-dev" = gtksourceview3.dev;
  "libgtkspell3-3-dev" = gtkspell3;
  "libhidapi-dev" = hidapi';
  "libjemalloc-dev" = jemalloc;
  "liblmdb-dev" = lmdb.dev;
  "liblua5.2-dev" = lua_5_2;
  "libnl-3-dev" = libnl;
  "libnl-route-3-dev" = libnl;
  "libpq-dev" = postgresql;
  "librocksdb-dev" = rocksdb;
  "libseccomp-dev" = libseccomp.dev;
  "libsqlite3-dev" = sqlite.dev;
  "libssl-dev" = openssl.dev;
  "libzmq3-dev" = zeromq3;
  "linux-libc-dev" = glibc.dev;
  "m4" = pkgsBuildBuild.m4;
  "ncurses-dev" = ncurses.dev;
  "perl" = pkgsBuildBuild.perl;
  "pkg-config" = pkgsBuildBuild.pkg-config;
  "zlib1g-dev" = zlib.dev;
}
