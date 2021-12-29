inputs: pkgs:
{
  inherit (import ./0install.nix inputs pkgs) "0install";
  inherit (import ./frama-c.nix inputs pkgs) frama-c;
  inherit (import ./opam2json.nix inputs pkgs) opam2json;
  inherit (import ./opam-ed.nix inputs pkgs) opam-ed;
  opam2json-static = (import ./opam2json-static.nix inputs pkgs).opam2json;
  inherit (import ./tezos.nix inputs pkgs) tezos tezos-client tezos-node;
}
