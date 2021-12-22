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
}
