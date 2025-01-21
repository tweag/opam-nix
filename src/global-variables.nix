hostPlatform: {
  opam-version = "2.0";
  root = "/tmp/opam";
  jobs = "$NIX_BUILD_CORES";
  make = "make";
  arch = if hostPlatform.uname.processor == "aarch64" then "arm64" else hostPlatform.uname.processor;
  os =
    if hostPlatform.isDarwin then
      "macos"
    else if hostPlatform.isLinux then
      "linux"
    else
      throw "${hostPlatform.uname.system} not supported";
  os-distribution = if hostPlatform.isDarwin then "homebrew" else "debian";
  os-family = if hostPlatform.isDarwin then "homebrew" else "debian"; # There are very few os-distribution = nixos packages
  os-version = "system";
  ocaml-native = true;
}
