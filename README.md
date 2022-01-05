# `opam-nix`

Turn opam-based OCaml projects into Nix derivations.


## TL;DR

### Templates

- `nix flake new my-package -t github:tweag/opam-nix`

### Examples

- [Building a package from opam-repository](./examples/0install/flake.nix)
- [Building a package from a custom github repository](./examples/opam2json/flake.nix)
- [Building a static version of a package using compiler from nixpkgs](./examples/opam-ed/flake.nix)
- [Building a static version of a package using the compiler from opam](./examples/opam2json-static/flake.nix)
- [Building a GUI package](./examples/frama-c/flake.nix)
- [Building the entirety of Tezos](./examples/tezos/flake.nix)

All examples are checks and packages, so you can do e.g. `nix build
github:tweag/opam-nix#opam-ed` to try them out individually, or `nix
flake check github:tweag/opam-nix` to build them all.

### What if I want to...

_Build an opam-based project_: use [`buildOpamProject`](#buildOpamProject)

_Build a dune-based project_: use [`buildDuneProject`](#buildDuneProject)

## Terminology

### Package

`Derivation`

An `opam-nix` "Package" is just a nixpkgs-based derivation which has
some additional properties. It corresponds to an opam package (more
specifically, it directly corresponds to an opam package installed in
some switch, switch being the [Scope](#Scope)).

Its output contains an empty file `nix-support/is-opam-nix-package`,
and also it has a `nix-support/setup-hook` setting some internal
variables, `OCAMLPATH`, `CAML_LD_LIBRARY_PATH`, and other variables
exported by packages using `variables` in `<pkgname>.config` or
`setenv` in `<pkgname>.opam`.

The derivation has a `passthru.pkgdef` attribute, which can be used to
get information about the opam file this Package came from.

The behaviour of the build script can be controlled using build-time
environment variables. If you want to set an opam environment variable
(be it for substitution or a package filter), you can do so by passing
it to `overrideAttrs` of the package with a special transformation
applied to the variable's name: replace `-` and `+` in the name with
underscores (`_`), replace all `:` (separators between package names
and their corresponding variables) with two underscores (`__`), and
prepend `opam__`. For example, if you want to get a package `cmdliner`
with `conf-g++:installed` set to `true`, do `cmdliner.overrideAttrs
(_: { opam__conf_g____installed = "true"; })`

If you wish to change the build in some other arbitrary way, do so as
you would with any nixpkgs package. You can override phases, but note
that `configurePhase` is special and should not be overriden (unless
you read `builder.nix` and understand what it is doing).

### Repository

`Path or Derivation`

A repository is understood in the same way as for opam itself. It is a
directory (or a derivation producing a directory) which contains at
least `repo` and `packages/`. Directories in `packages` must be
package names, directories in those must be of the format
`name.version`, and each such subdirectory must have at least an
`opam` file.

If a repository is a derivation, it may contain `passthru.sourceMap`,
which maps package names to their corresponding sources.

### Query

`{ ${package_name} = package_version : String or null; ... }`

A "query" is a attrset, mapping from package names to package
versions. It is used to "query" the repositories for the required
packages and their versions. A special version of `null` means
"latest" for functions dealing with version resolution
(i.e. `opamList`), and shouldn't be used elsewhere.

### Scope

```
{ overrideScope' = (Scope → Scope → Scope) → Scope
; callPackage = (Dependencies → Package) → Dependencies → Package
; ${package_name} = package : Package; ... }
```

A [nixpkgs "scope" (package
set)](https://github.com/NixOS/nixpkgs/blob/5f596e2bf5bea4a5d378883b37fc124fb39f5447/lib/customisation.nix#L199).
The scope is self-referential, i.e. packages in the set may refer to
other packages from that same set. A scope corresponds to an opam
switch, with the most important difference being that packages are
built in isolation and can't alter the outputs of other packages, or
use packages which aren't in their dependency tree.

Note that there can only be one version of each package in the set,
due to constraints in OCaml's way of linking.

`overrideScope'` can be used to apply overlays to the scope, and
`callPackage` can be used to get `Package`s from the output of
`opam2nix`, with dependencies supplied from the scope.

## Public-facing API

Public-facing API is presented in the `lib` output of the flake. It is
mapped over the platforms, e.g. `lib.x86_64-linux` provides the
functions usable on x86_64-linux. Functions documented below reside in
those per-platform package sets, so if you want to use
e.g. `makeOpamRepo`, you'll have to use
`opam-nix.lib.x86_64-linux.makeOpamRepo`. All examples assume that the
relevant per-platform `lib` is in scope, something like this flake:

```nix
{
  inputs.opam-nix.url = "github:tweag/opam-nix";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, opam-nix, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      with opam-nix.lib.${system}; {
        defaultPackage = # <example goes here>
      });
}
```

Or this flake-less expression:

```
with (import (builtins.fetchTarball "https://github.com/tweag/opam-nix/archive/main.tar.gz")).lib.${builtins.currentSystem};
# example goes here
```

You can instantiate `opam.nix` yourself, by passing at least some
`pkgs` (containing `opam2json`), and optionally `opam-repository` for
use as the default repository (if you don't pass `opam-repository`,
`repos` argument becomes required everywhere).

### `queryToScope`

```
{ repos = ?[Repository]
; pkgs = ?Nixpkgs
; overlays = ?[Overlay]
; env = ?{ ${var_name} = value : String; ... } }
→ Query
→ Scope
```

Turn a `Query` into a `Scope`.

Special value of `null` can be passed as a version in the `Query` to
let opam figure out the latest possible version for the package.

The first argument allows providing custom repositories & top-level
nixpkgs, adding overlays and passing an environment to the resolver.

#### `repos`, `env` & version resolution

Versions are resolved using upstream opam. The passed repositories
(`repos`, containing `opam-repository` by default) are merged and then
`opam admin list --resolve` is called on the resulting
directory. Package versions from earlier repositories take precedence
over package versions from later repositories. `env` allows to pass
additional "environment" to `opam admin list`, affecting its version
resolution decisions. See [`man
opam-admin`](https://opam.ocaml.org/doc/man/opam-admin.html) for
further information about the environment.

When a repository in `repos` is a derivation and contains
`passthru.sourceMap`, sources for packages taken from that repository
are taken from that source map.

#### `pkgs` & `overlays`

By default, `pkgs` match the `pkgs` argument to `opam.nix`, which, in
turn, is the `nixpkgs` input of the flake. `overlays` default to
`defaultOverlay` and `staticOverlay` in case the passed nixpkgs appear
to be targeting static building.

#### Examples

Build a package from `opam-repository`, using all sane defaults:

<div class=example id=opam-ed-defaults dir=empty>



```nix
(queryToScope { } { opam-ed = null; }).opam-ed
```

</div>

Build a specific version of the package, overriding some dependencies:

<div class=example id=opam-ed-overrides dir=empty>



```nix
let
  scope = queryToScope { } { opam-ed = "0.3"; };
  overlay = self: super: {
    opam-file-format = super.opam-file-format.overrideAttrs
      (oa: { opam__ocaml__native = "true"; });
  };
in (scope.overrideScope' overlay).opam-ed
```

</div>

Pass static nixpkgs (to get statically linked libraries and
executables):

<div class=example id=opam-ed-static dir=empty></div>



```nix
let
  scope = queryToScope {
    pkgs = pkgsStatic;
  } { opam-ed = null; };
in scope.opam-ed
```

### `buildOpamProject`

```
{ repos = ?[Repository]
; pkgs = ?Nixpkgs
; overlays = ?[Overlay]
; env = ?{ ${var_name} = value : String; ... } }
→ project: Path
→ Query
→ Scope
```

A convenience wrapper around `queryToScope`.

Turn an opam project (found in the directory passed as the first
argument) into a `Scope`. More concretely, create the scope with the
latest versions of all the packages found in the "project", together
with package versions from the `Query`.

The first argument is the same as the first argument of
`queryToScope`, except the repository produced by calling
`makeOpamRepo` on the project directory is prepended to `repos`.

#### Examples

Build a package from a local directory:

<div class=example id=build-opam-project dir=my-package>



```nix
(buildOpamProject { } ./. { }).my-package
```

</div>

Build a package from a local directory, forcing opam to use the
non-"system" compiler:

<div class=example id=build-opam-project-base-compiler dir=my-package>



```nix
(buildOpamProject { } ./. { ocaml-base-compiler = null; }).my-package
```

</div>

Building a statically linked library or binary from a local directory:

<div class=example id=build-opam-project-static dir=my-package>



```nix
(buildOpamProject { pkgs = pkgsStatic; } ./. { }).my-package
```

</div>

### `buildDuneProject`

```
{ repos = ?[Repository]
; pkgs = ?Nixpkgs
; overlays = ?[Overlay]
; env = ?{ ${var_name} = value : String; ... } }
→ name: String
→ project: Path
→ Query
→ Scope
```

A convenience wrapper around `buildOpamProject`. Behaves exactly as
`buildOpamProject`, except runs `dune build ${name}.opam` in an
environment with `dune_2` and `ocaml` from nixpkgs beforehand. This is
supposed to be used with dune's `generate_opam_files`

#### Examples

Build a local project which uses dune and doesn't have an opam file:


<div class=example id=build-dune-project dir=my-package-dune>



```nix
(buildDuneProject { } "my-package" ./. { }).my-package
```

</div>

### `makeOpamRepo`

`Path → Derivation`

Traverse a directory, looking for `opam` files and collecting them
into a repository in a format understood by `opam`. The resulting
derivation will also provide `passthru.sourceMap`, which is a map from
package names to package sources taken from the original `Path`.

Packages for which the version can not be inferred get `local` as
their version.

Note that all `opam` files in this directory will be evaluated using
`importOpam`, to get their corresponding package names and versions.

#### Examples

Build a package from a local directory, which depends on packages from opam-repository:

<div class=example id=make-opam-repo dir=my-package>



```nix
let
  repos = [ (makeOpamRepo ./.) opamRepository ];
  scope = queryToScope { inherit repos; } { my-package = null; };
in scope.my-package
```

</div>

### `listRepo`

`Repository → {${package_name} → [version : String]}`

Produce a mapping from package names to lists of versions (sorted
older-to-newer) for an opam repository.

### `opamImport`

```
{ repos = ?[Repository]
; pkgs = ?Nixpkgs
; overlays = ?[Overlay] }
→ Path
→ Scope
```

Import an opam switch, similarly to `opam import`, and provide a
package combining all the packages installed in that switch. `repos`,
`pkgs`, `overlays` and `Scope` are understood identically to
`queryToScope`, except no version resolution is performed.

### `opam2nix`

`{ src = Path; opamFile = ?Path; name = ?String; version = ?String; } → Dependencies → Package`

Produce a callPackage-able `Package` from an opam file. This should be
called using `callPackage` from a `Scope`. Note that you are
responsible to ensure that the package versions in `Scope` are
consistent with package versions required by the package. May be
useful in conjunction with `opamImport`.

#### Examples

<div class=example id=opam-import dir=opam-import>



```nix
let
  scope = opamImport { } ./opam.export;
  pkg = opam2nix { src = ./.; name = "my-package"; };
in scope.callPackage pkg {}
```

</div>

### `defaultOverlay`, `staticOverlay`

`Overlay : Scope → Scope → Scope`

Overlays for the `Scope`'s. Contain enough to build the
examples. Apply with `overrideScope'`.

### Materialization

```
materialize :
{ repos = ?[Repository]
; env = ?{ ${var_name} = value : String; ... } }
→ Query
→ Path
```

```
materializedDefsToScope :
{ pkgs = ?Nixpkgs
; overlays = ?[Overlay] }
→ Path
→ Scope
```

`materialize` resolves a query in much the same way as `queryToScope`
would, but instead of producing a scope it produces a JSON file
containing all the package definitions for the packages required by
the query.

`materializedDefsToScope` takes a JSON file with package defintions as
produced by `materialize` and turns it into a scope. It is quick, does
not use IFD or have any dependency on `opam` or `opam2json`.

The drawback of materialization is having a generated file commited to
your repository.

There also is a convenience script that wraps `materialize`, called
`opam-nix-gen`. You can use it to generate the defs, and then pass
that file to `materializedDefsToScope` in your `flake.nix`.


#### Examples

First, create a `package-defs.json`:

```sh
opam-nix-gen -l . -p my-package > package-defs.json
```

Then, import it:

<div class=example id=my-package-materialized dir=my-package>




```nix
(materializedDefsToScope { sourceMap.my-package = ./.; } ./package-defs.json).my-package
```

</div>

### `fromOpam` / `importOpam`

`fromOpam : String → {...}`

`importOpam : Path → {...}`

Generate a nix attribute set from the opam file. This is just a Nix
representation of the JSON produced by `opam2json`.

### Lower-level functions

`joinRepos : [Repository] → Repository`

`opamList : Repository → Env → Query → [String]`

`opamListToQuery : [String] → Query`

`queryToDefs : [Repository] → Query → Defs`

`defsToScope : Nixpkgs → Defs → Scope`

`applyOverlays : [Overlay] → Scope → Scope`

`opamList` resolves package versions using the repo (first argument)
and environment (second argument). Note that it accepts only one
repo. If you want to pass multiple repositories, merge them together
yourself with `joinRepos`. The result of `opamList` is a list of
strings, each containing a package name and a package version. Use
`opamListToQuery` to turn this list into a "`Query`" (but with all the
versions specified).

`queryToDefs` takes a query (with all the version specified,
e.g. produced by `opamListToQuery` or by reading the `installed`
section of `opam.export` file) and produces an attribute set of
package definitions (using `importOpam`).

`defsToScope` takes a nixpkgs instantiataion and an attribute set of
definitions (as produced by `queryToDefs`) and produces a `Scope`.

`applyOverlays` applies a list of overlays to a scope.

#### `Defs` (set of package definitions)

The attribute set of package definitions has package names as
attribute names, and package definitions as nix attrsets. These are
basically the nix representation of
[opam2json](https://github.com/tweag/opam2json/) output. The format of
opam files is described here:
https://opam.ocaml.org/doc/Manual.html#opam .

### Examples

Build a local package, using an exported opam switch and some
"vendored" dependencies, and applying some local overlay on top.

```nix
let
  pkgs = import <nixpkgs> { };

  repos = [
    (opam-nix.makeOpamRepo ./.) # "Pin" vendored packages
    inputs.opam-repository
  ];

  export =
    opam-nix.opamListToQuery (opam-nix.fromOPAM ./opam.export).installed;

  vendored-packages = {
    "my-vendored-package" = "local";
    "my-other-vendored-package" = "v1.2.3";
    "my-package" = "local"; # Note: you can't use null here!
  };

  myOverlay = import ./overlay.nix;

  scope = applyOverlays [ defaultOverlay myOverlay ]
    (defsToScope pkgs (queryToDefs repos (export // vendored-packages)));
in scope.my-package
```

### Auxiliary functions

`splitNameVer : String → { name = String; version = String; }`

`nameVerToValuePair : String → { name = String; value = String; }`

Split opam's package definition (`name.version`) into
components. `nameVerToValuePair` is useful together with
`listToAttrs`.
