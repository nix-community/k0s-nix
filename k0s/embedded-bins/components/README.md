# components

## The component derivations

This directory holds one derivation per payload binary, keyed by minor:
`default.nix` turns a minor's JSON into the arguments each component
takes, so a component file knows the pins it needs and nothing about the
file they came from. `k0s/embedded-bins/pins.nix` is the reader both it
and `checks/embedded-bins.nix` use.

A component overrides the nixpkgs package rather than reproducing
upstream's Dockerfile. nixpkgs already carries the build knowledge - its
`runc` sets `BUILDTAGS+=seccomp` and takes `libseccomp` as an argument -
so what the override adds is k0s's version, its linker flags and its
libseccomp pin. konnectivity is the exception, and only because nixpkgs
packages no `apiserver-network-proxy` to override.

Two deliberate deviations from upstream, each asserted rather than left
to trust - the first while the component evaluates, the second by
`checks/embedded-bins-runc.nix`:

- **Dynamic linking.** `build_go_ldflags_extra` is `-extldflags=-static`
  wherever it is set at all, and it is not reproduced. nixpkgs ships no
  static `libc`, `libseccomp` or `libresolv`, and the payload is
  extracted onto a node whose store already holds what the binary links
  against. `go-ldflags.nix` asserts that the field is absent or holds
  nothing but the static flag, so a pin this would otherwise drop stops
  the build. etcd is the component that leaves it unset.
- **No wrapper.** nixpkgs wraps `runc` to prepend
  `/run/current-system/systemd/bin` to `PATH`. A payload binary that
  execs a store path defeats the point of vendoring it, and k0s prepends
  its own bin directory to the `PATH` of what it supervises.

A third deviation carries no assertion, because the pins hold nothing it
could be checked against: the Go toolchain is nixpkgs' rather than the
`go_version` each minor pins, for every component and minor, as nixpkgs'
k3s does. Matching the pin would buy a version number rather than
upstream's toolchain, nixpkgs' Go being patched, and it would want
re-pinning on every k0s bump. What moves a component off nixpkgs' Go is
a build that fails under it, rather than a rule about matching upstream.

### containerd

The one component whose binary set is a pin of its own. k0s passes
`--build-arg CONTAINERD_BINS`, fed from a `containerd_bins` variable that
is not one of the `_build_*` suffixes `k0s/embedded-bins/extract.py`
reads, and the set moves with the containerd major - four binaries at
k0s 1.33, two at 1.36.
The component takes the `containerd`-prefixed names out of
`payloadBinaries`, which names the same set on every packaged minor, and
passes them as `COMMANDS`. That also suppresses the `COMMANDS +=` in
containerd's `Makefile.linux`, so `ctr` and `containerd-stress` stay out.

nixpkgs' `makeFlags` are replaced rather than added to, in a build phase
of the component's own. The list is composed with `rec`, so `VERSION` and
`REVISION` would keep naming 2.3.3 while 1.33 to 1.35 build 1.7.34; and
nixpkgs interpolates it unquoted, which would split the tags and the
linker flags into `make` targets. The tags go in as `GO_BUILDTAGS`
whatever the minor: both Makefiles derive `GO_TAGS` from it, so the pin's
own spelling - `apparmor selinux` at 1.36, `apparmor,selinux` below -
passes through verbatim.

`REVISION` is always passed, so the Makefile's `git rev-parse` never runs
in a sandbox with no repository to read. 1.36 pins one and the binary
reports it; below that nothing does. Upstream uses the pin to verify its
clone rather than to stamp, and here the fetch hash makes that assertion
instead.

### etcd

nixpkgs keeps a package per etcd minor series, and both k0s pins land on
one: 3.5.33 at k0s 1.33, 3.6.14 above it. `etcd.nix` selects on the
pinned series rather than on the k0s minor, and asserts that the package
it picked carries the pinned version - a nixpkgs bump has to fail there
rather than on a vendor hash built for another version.

Only the server is a payload binary. nixpkgs joins it with `etcdctl` and
`etcdutl`, each a derivation of its own, and the component takes
`deps.etcdserver`, whose `bin/` holds `etcd` alone.
`k0s/embedded-bins/payload.nix` takes whatever `bin/` holds, so the join
reaching the payload would stage two binaries k0s never asks for;
`checks/embedded-bins-etcd.nix` asserts it does not.

The binary reports `Git SHA: GitNotFound`. Upstream's Dockerfile clones
the repository and stamps the short SHA, but the source here is a tarball
with no repository in it - git in the sandbox would find nothing to read,
and cloning wants a network it does not have. nixpkgs stamps upstream's
own no-git fallback deliberately, and the check asserts it so it stays a
decision rather than a surprise.

### iptables

The only component with no Go pins at all. `Makefile.variables` carries a
version and a build image and nothing else, and upstream's static linking
- `--enable-static --disable-shared` with `LDFLAGS=-all-static` - is in
the Dockerfile's own `configure` call, which
`k0s/embedded-bins/extract.py` never reads. So there is nothing for
`go-ldflags.nix` to assert against here; the
deviation is the dynamic linking above, whose reasoning does not turn on
the component being written in Go.

k0s pins 1.8.11 below 1.36 and 1.8.13 at it. The override runs on every
minor rather than only where the versions differ, so one path is
exercised instead of two that drift apart as the pins move.

`k0s/embedded-bins/payload.nix` takes whatever `bin/` holds and the
nixpkgs package installs some forty entries, so the component installs
the two multi binaries into an output of its own. k0s stages both - it
errors if either is missing - and makes the `iptables`, `iptables-save`,
`iptables-restore` and `ip6tables` symlinks itself once it has detected a
mode, so the payload carries no symlink.

Where upstream's static build compiles the extensions in, these dlopen
them out of the `lib` output at runtime. That is the sharpest case for
the [`payload-closure` file](../../README.md#how-the-payload-is-attached):
without it the extensions are what a collection takes first, and
`checks/embedded-bins-iptables.nix` loads one to prove the path resolves.

### keepalived

The second C build, and the only payload binary a single node never
stages: `cplb_linux.go` stages it when the control plane load balancer
is configured, and nothing else asks for it. That is what splits
`checks/source-build-vm.nix`'s two lists apart.

nixpkgs carries 2.3.4, which is the pin at 1.34, 1.35 and 1.36; only
1.33 differs, at 2.2.8. The override runs on every minor for the reason
iptables' does.

It is built with k0s's feature set rather than nixpkgs'. Upstream's
Dockerfile installs openssl and libnl3 and nothing else, so what k0s
ships has VRRP and LVS alone, where nixpkgs adds `file`, `libmnl`,
`libnftnl` and net-snmp. Nothing k0s configures reaches those - its VRRP
template writes `auth_type PASS`, and it runs the payload's own xtables
binaries for the NAT rather than asking keepalived to. `-v` reports the
detected feature set as two compiled-in lists, so
`checks/embedded-bins-keepalived.nix` asserts the decision against the
binary rather than the derivation.

`--disable-dynamic-linking` is passed as the pin has it, and it is not
the static linking the payload drops. It makes keepalived link libiptc,
libipset and libnl at build time instead of `dlopen`ing them by soname -
the trap iptables' extensions already cost a `payload-closure` entry to
avoid - and with ipset absent it changes nothing.

The source is the tarball the pin names rather than nixpkgs' GitHub
archive, and not only because the pin says so. The release tarball ships
`lib/git-commit.h`, which is where the version string's date comes from;
an archive carries none, and `lib/Makefile.am` then derives one from the
newest file mtime. That is 1 in a store path, so nixpkgs' own build
reports `Keepalived v2.3.4 (01/01,1970)`.

`configure` compiles its own command line into the binary, so the
package's prefix and each buildInput's `-dev` pkg-config path are
strings in it, and `payload-closure` would hand a node the build
environment of a binary it already has. `remove-references-to` takes
them back out; what that also mangles is the default configuration path,
which k0s never reads because it always passes `--use-file`.

Like iptables, the component installs the one binary itself: keepalived
goes to `sbin` and `bin` gets a `genhash` symlink, where
`k0s/embedded-bins/payload.nix` takes whatever `bin/` holds.

### kine

Three versions across the four minors - 0.13.19 at 1.33, 0.14.16 at 1.34
and 1.35, 0.16.3 at 1.36 - and nixpkgs packages none of them, so the
source is overridden everywhere and each version owes a vendor hash of
its own. The table is keyed by kine version rather than by k0s minor,
which is what lets 1.34 and 1.35 share an entry.

Two pins are what the component adds beyond the version. The `nats`
build tag compiles the embedded NATS server in, and nixpkgs sets no tags
at all; `build_go_cgo_cflags` replaces nixpkgs' value rather than adding
to it, since nixpkgs sets `-DSQLITE_ENABLE_DBSTAT_VTAB=1` on every
version and only 1.33 pins it. The linker flags replace nixpkgs' for the
same reason: its stamps name the version it packages, and a second `-X`
on one symbol would leave the binary's identity to whichever the linker
takes last.

`GitCommit` is stamped `unknown`. Upstream builds it from `git rev-parse`
in a clone, the tarball-has-no-git case etcd meets differently - kine has
no fallback of its own, so nixpkgs' answer is kept and
`checks/embedded-bins-kine.nix` reads it back out of `kine --version`.

The nixpkgs package runs kine's test suite and this component does not.
The `nats` tag compiles in a suite nixpkgs never builds, and at 0.13.19
it fails against its own embedded server - a different set of tests each
run. What the check reads back instead is that the tag took,
by the embedded server's constructor being a symbol in the binary, and
that cgo was on, by the binary carrying an interpreter. cgo off would
leave `go-sqlite3` a stub that builds and fails at runtime, and it is on
by default rather than by a pin: `kine_build_go_cgo_enabled` is commented
out upstream, so the component asserts the field is absent.

### konnectivity

The one component nixpkgs does not package, so it is a `buildGoModule`
of its own rather than an override. Two things upstream's Dockerfile
does are not reproduced. It clones the tag and runs `make gen` first -
protoc and mockgen `go install`ed over a network the sandbox does not
have - and every file that generates is committed in the source, so the
build reads them out of the tarball and the generators never run. The
tarball also carries `vendor/`, which is why this is the one Go
component owing no vendor hash.

It is also the only binary here that reports no version. Upstream passes
`-w -s` and no `-X`, and the server has no version flag and no version
subcommand, so nothing can be read back out of it. What
`checks/embedded-bins-konnectivity.nix` reads instead is the Go build
info: that `cmd/server` is the package built, and that `CGO_ENABLED`
matches the pin. Tying a minor's tarball to the version it records is
left to the component, which asserts the fetch URL names it.

`build_go_flags` is `-a`, and it is dropped rather than passed on: it
forces a rebuild of what is already built, which buys nothing in a
sandbox that has built none. The component asserts the pin holds nothing
else, so a flag added upstream stops the build instead of vanishing.

The Dockerfile builds `bin/proxy-server` and renames it to
`konnectivity-server` on the way into the image. The rename is the
component's, because the payload entry has to be the name k0s stages.

### kubernetes

The last of the single node components, and the second whose binary set
is out of band: `kubernetes_bins` is a plain variable in
`embedded-bins/Makefile`, the same class as `containerd_bins`, and
answered the same way: the set comes out of the extracted data rather
than a second list kept here, so a minor added later carries its own.
The component filters the `kube`-prefixed names out of
`payloadBinaries` - `kubelet`, `kube-apiserver`, `kube-scheduler` and
`kube-controller-manager` on every packaged minor, with `keepalived` not
colliding. They go in as the `components` argument the nixpkgs package
already takes, which is also what sets `WHAT`.

nixpkgs' `installPhase` is replaced rather than extended, and `outputs`
drops to `out`. It symlinks `kubectl` in, substitutes `kube-addons`,
installs man pages and generates shell completions by *running*
`kubeadm` - which an overridden `components` no longer builds, so the
phase fails on a binary that is not there.
`k0s/embedded-bins/payload.nix` takes whatever `bin/` holds, so the
symlink would have staged a binary k0s never asks for even if it had run.

**The version stamp does not transfer as an environment variable.** The
source is a GitHub archive, so the placeholders `git archive`
substitutes are already expanded in `hack/lib/version.sh`: it carries
the commit, `KUBE_GIT_TREE_STATE="archive"` and the tag literally, reads
them before it looks at the environment, and *overwrites* what it finds.
Upstream's `export KUBE_GIT_VERSION="v$VERSION+k0s"` only survives
because its Dockerfile clones with git, where the placeholders are
unexpanded and the block is skipped. `KUBE_GIT_VERSION_FILE` is the
mechanism that does transfer - `get_version_vars` sources it and returns
ahead of everything else - so the component writes one, taking the
commit back out of the source's own archive stamp and supplying the
major and minor the skipped semver parse would have derived. The `+k0s`
suffix is upstream's, and it is what a node reports as its kubelet
version.

Because that version is stamped rather than read, no binary can report a
source other than the pinned one, and the check cannot tell the two
apart - where etcd asserts the nixpkgs package's version and containerd
reads the daemon's own. So the component asserts instead that the tag in
the archive stamp is the version the pin names, which is what would catch
a pin moved without its `fetch` entry.

`SOURCE_DATE_EPOCH` is exported in the build phase rather than set on
the derivation. k8s renders `buildDate` from it, and
`set-source-date-epoch-to-latest.sh` raises the variable to the newest
mtime under `sourceRoot` *after* unpacking - a store path carries mtime
1, so a value set any earlier comes out a second late. The constant is
`k0s/source.nix`'s, so k0s and its payload agree on the date they were not
built on.

**`riscv64.patch` is not applied.** Upstream's Dockerfile applies it
unconditionally, and all it does is append `linux/riscv64` to the four
`KUBE_SUPPORTED_*_PLATFORMS` lists and teach `kube::util::host_arch` the
name. Neither is read by a `make WHAT=` build: `build_binaries` defaults
to the host platform and never consults those lists, which belong to the
release tooling. So the patch is unreachable on every platform k0s-nix
builds, and applying it would make this component depend on the k0s
source tarball to change nothing.

`checks/embedded-bins-kubernetes.nix` reads `--version=raw` out of each
binary, which renders the whole `version.Info` struct, so one call
carries every stamp the build is meant to have set. `GitVersion` and
`GitTreeState` are the two that say the version file was read at all:
without it the archive's own values win and report the plain version and
`archive`.

### runc

The only component whose pin is not in `Makefile.variables` at all.
libseccomp is an `ARG LIBSECCOMP_VERSION` in runc's Dockerfile, so it
moves independently of the version nixpkgs carries and would be dropped
in silence by anything reading the variables file alone - which is the
case the [guards](../README.md#the-guards) were written for. The
component reads it as `argpin_LIBSECCOMP_VERSION` and overrides nixpkgs'
`libseccomp` with that version and the source the pin names, so what runc
links against is k0s's choice rather than nixpkgs'.

That is also the only thing telling this build apart from the packaged
one. `runc --version` reports the libseccomp it linked against beside its
own version, and `checks/embedded-bins-runc.nix` reads both lines back.

nixpkgs' `makeFlags` are replaced by a build phase of the component's
own, for the reason containerd's are: nixpkgs interpolates the list
unquoted, which would split `EXTRA_LDFLAGS` on its spaces. Passing
`BUILDTAGS` directly also makes the pinned tags the only ones in play,
where adding to nixpkgs' would leave its `BUILDTAGS+=seccomp` beside
them. The check reads `runc features` and asserts
`linux.seccomp.enabled`, so the tag having taken is established by the
binary rather than by the flags going in.

runc is the component the no-wrapper rule above binds - nixpkgs is what
wraps it - so the install phase places the binary and its man pages
itself. The check asserts `bin/` holds nothing but `runc`, a wrapper
being the one thing that would leave the payload exec'ing a store path.

## Read before packaging a component

- Upstream's container build is not reproducible on its own terms - it
  installs toolchains from live distro repositories - and does not run in
  a Nix sandbox at all. What transfers is the specification: versions,
  tags, linker flags. Not the mechanics.
- `payloadBinaries` is upstream's own list and it moves: fifteen entries
  at 1.33, thirteen at 1.36.
- Not every `--build-arg` comes from the suffix scheme. `CONTAINERD_BINS`
  is fed from a plain `Makefile` variable, so the guards do not cover it.
- `extra_urls` carries what a component fetches besides its own source -
  libseccomp for runc, and an upstream patch for containerd at 1.34 and
  1.35 which 1.36 no longer needs.
- `kubernetes/` also carries a `riscv64.patch` in the k0s tree, which is
  applied by its Dockerfile rather than fetched.
