{
  opam-version = "2.0";
  root = "/tmp/opam";
  jobs = "$NIX_BUILD_CORES";
  make = "make";
  arch = "x86_64-linux";
  os = "linux";
  os-distribution = "debian";
  os-family = "debian"; # There are very few os-distribution = nixos packages
  os-version = "system";
  ocaml-native = true;
}
