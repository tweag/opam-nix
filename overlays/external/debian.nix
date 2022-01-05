# Map from debian to nixpkgs
pkgs:
with pkgs;
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
in {
  "autoconf" = pkgsBuildBuild.autoconf;
  "capnproto" = capnproto;
  "cargo" = cargo';
  "debianutils" = which; # eurgh
  "g++" = pkgsBuildHost.gcc;
  "git" = git;
  "gnupg" = gnupg;
  "graphviz" = graphviz;
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
  "libgtk-3-dev" = gtk3.dev;
  "libgtk2.0-dev" = gtk2.dev;
  "libgtksourceview-3.0-dev" = gtksourceview3.dev;
  "libgtksourceview2.0-dev" = gtksourceview';
  "libgtkspell3-3-dev" = gtkspell3;
  "libhidapi-dev" = hidapi';
  "libjemalloc-dev" = jemalloc;
  "liblua5.2-dev" = lua_5_2;
  "libpq-dev" = postgresql;
  "libsqlite3-dev" = sqlite.dev;
  "libssl-dev" = openssl.dev;
  "libzmq3-dev" = zeromq3;
  "m4" = pkgsBuildBuild.m4;
  "ncurses-dev" = ncurses.dev;
  "perl" = pkgsBuildBuild.perl;
  "pkg-config" = pkgsBuildBuild.pkg-config;
  "time" = time;
  "unzip" = unzip;
  "zlib1g-dev" = zlib.dev;
}
