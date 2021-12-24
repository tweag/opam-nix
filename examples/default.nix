inputs: pkgs:
{
  inherit (import ./0install.nix inputs pkgs) "0install";
  inherit (import ./frama-c.nix inputs pkgs) frama-c;
  inherit (import ./mina.nix inputs pkgs) mina;
  inherit (import ./opam2json.nix inputs pkgs) opam2json;
  inherit (import ./tezos.nix inputs pkgs) tezos;
}
