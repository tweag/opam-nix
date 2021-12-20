pkgs: with pkgs.lib; rec {
  opam-version = "2.0";
  root = "/tmp/opam";
  jobs = "4"; # FIXME
  make = "make";
  arch = head (splitString "-" pkgs.system);
  os = last (splitString "-" pkgs.system);
  os-distribution = os;
  os-family = "nixos";
  os-version = "system";
}
