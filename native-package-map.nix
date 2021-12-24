# Map from debian to nixpkgs package names
pkgs:
with pkgs; {
  "g++" = gcc;
  "liblua5.2-dev" = lua_5_2;
  "libpq-dev" = postgresql;
  "libbluetooth-dev" = bluez5;
  "libzmq3-dev" = zeromq3;
  "libgtkspell3-3-dev" = gtkspell3;

  # I got bored... Let's skip to the stuff I actually need

  "libgmp-dev" = gmp.dev;
  "perl" = perl;
  "pkg-config" = pkg-config;
  "libssl-dev" = openssl.dev;
  "libffi-dev" = libffi.dev;
  "m4" = m4;
  "debianutils" = which; # eurgh
  "libjemalloc-dev" = jemalloc;
  "libev-dev" = libev;
  "cargo" = buildEnv { name = "cargo"; paths = [ cargo rustc ]; };
  "zlib1g-dev" = zlib.dev;
  "libcurl4-gnutls-dev" = curl.dev;
  "gnupg" = gnupg;
  "unzip" = unzip;
  "libcairo2-dev" = cairo.dev;
  "libgtk-3-dev" = gtk3.dev;
  "libexpat1-dev" = expat.dev;
  "libglib2.0-dev" = glib.dev;
  "autoconf" = autoconf;
  "graphviz" = graphviz;
  "libgtk2.0-dev" = gtk2.dev;
  "libgtksourceview2.0-dev" = gtksourceview.dev;
  "libgnomecanvas2-dev" = gnome2.libgnomecanvas.dev;
  "libgtksourceview-3.0-dev" = gtksourceview3.dev;
}
