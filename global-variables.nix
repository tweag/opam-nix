pkgs: with pkgs.lib; rec {
  opam-version = "2.0";
  root = "/tmp/opam";
  jobs = "$NIX_BUILD_CORES";
  make = "make";
  arch = head (splitString "-" pkgs.system);
  os = last (splitString "-" pkgs.system);
  os-distribution = os;
  os-family = "debian"; # There are very few os-distribution = nixos packages
  os-version = "system";
}
