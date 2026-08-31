# k0s

Two packages per minor, from the same pin. `k0s` and the `k0s_1_33` to
`k0s_1_36` it aliases install the release binary upstream publishes,
fetched by `<minor>.nix` and refreshed by `update-script.bash`.
`k0s-source_1_33` to `k0s-source_1_36` build that same k0s from source
here, carrying a payload built from source with it.

A k0s release binary is the k0s executable with a payload of component
binaries carried behind it. Upstream builds each component in its own
container image, from the versions and build parameters in
`embedded-bins/Makefile.variables`. `embedded-bins/` reads those pins,
`embedded-bins/components/` turns them into a derivation per component,
and `source.nix` builds k0s and attaches the result.

Nothing caches this flake's outputs, so the source build is opted into
rather than defaulted to: `k0s` stays the fetched binary.

## The payload mechanism differs by minor

There are two of them, and which one a minor uses decides how the
payload is assembled.

- **1.36** appends a zip. `hack/zip-files` writes it, `cat` puts it
  behind `k0s.bare`, and `pkg/assets/stage.go` opens the running
  executable with `zip.OpenReader`, matching an entry by the plain
  binary name. A zip's index sits at its end, so both formats stay
  readable. The Go build knows nothing about the payload, which is what
  makes `k0s.bare` reusable: a component can move into the archive
  without rebuilding k0s.
- **1.33 to 1.35** compile an index in. `hack/gen-bindata` gzips each
  staged binary into one `bindata_linux` blob and generates
  `pkg/assets/zz_generated_offsets_linux.go`, an offset and size table
  that is compiled into the binary before the blob is appended. So the
  Go build depends on the components, and moving one into the payload
  rebuilds k0s.

`EMBEDDED_BINS_BUILDMODE=none` covers both: at 1.36 the `cat` is
skipped, and below it the `noembedbins` build tag selects the empty
`pkg/assets/offsets_other.go` stub instead of the generated table.
Without that tag a payload-less build below 1.36 does not compile at
all.

## The source build

`source.nix` builds k0s itself, one derivation per minor, against the
k0s source each minor's JSON already pins under the name `k0s`. It
offers two sets: `bare` carries no payload, and `withPayload` carries
whatever `embedded-bins/components/` has for that minor.
`checks/source-build.nix` proves the first, diffing `k0s version --json`
against the pins the binary was stamped from;
`checks/embedded-bins-payload.nix` and `checks/source-build-vm.nix`
prove the second, below - one reads the archive out of the binary, the
other boots a node on it. Nothing from nixpkgs is put on `PATH` to stand
in for a component the payload does not carry yet, because that would
run a combination upstream never ships.

It needs no codegen phase. The Makefile regenerates deepcopy functions,
CRDs and the clientset before every build, but only because the stamp
files it uses as targets are untracked - the generated sources
themselves are committed, and each generator runs through `go run
<tool>@<version>`, which wants the network.

**`CGO_ENABLED` is per minor, and it is not in `Makefile.variables`.**
It is 1 at 1.33 and 1.34, 0 at 1.35 and 1.36. Below 1.35 `pkg/backup`
reaches `github.com/rqlite/rqlite/db` behind nothing but a `unix` build
constraint, and rqlite needs the real `mattn/go-sqlite3`, which without
cgo compiles to a stub carrying none of the methods it calls. 1.36
dropped rqlite altogether.

The `Makefile` moved it, too: below 1.36 it is set on the `k0s` target
itself, from 1.36 on it is a plain variable and the recipe sits on
`k0s.bare`. So `extract.py` asks `make` to expand the build command
rather than parsing either shape, and `source.nix` keeps the value by
hand and compares the two. A disagreement stops the build, so a change
upstream makes here is looked at rather than followed - and a tree whose
build command cannot be found is refused by the
[guards](./embedded-bins/README.md#the-guards) like anything else.

## How the payload is attached

The two mechanisms above are two assembly paths, and `source.nix`
carries both.

At **1.36** the components are zipped by `embedded-bins/payload.nix` and
the archive is appended to the finished binary. The Go build takes no
argument from it, so it is the same derivation `bare` builds and a
component moving into the payload does not rebuild k0s.

**Below 1.36** the components are staged into
`embedded-bins/staging/linux/bin` in `preBuild` and `hack/gen-bindata`
is run over them, exactly as the Makefile does. It writes both halves of
the payload at once: the blob, and the offset table that locates entries
in it. The table is compiled in, so `noembedbins` comes off and the
build depends on the components; the blob leaves through a second
output, `bindata`.

Appending is a step of its own in both cases rather than part of the Go
build, because `fixupPhase` strips `$out/bin` and shrinks its RPATHs -
each of which rewrites the ELF and would discard whatever sits behind
it. That step also wraps the binary, and the order matters: `k0s` reads
the payload out of the executable it is running, and a wrapper is not
that executable. The real binary is `libexec/k0s`, which is what carries
the payload, and `bin/k0s` is the wrapper that execs it.

The components are named again in `$out/nix-support/payload-closure`,
which is what makes them references of the package. Compressed into the
payload, a store path is not a string the reference scanner can find, so
without that file a collection takes the libraries the staged binaries
were linked against and leaves the payload unrunnable - the very thing
dynamic linking assumes will not happen. References are transitive, so
naming the component is enough to hold its own closure with it.

`checks/embedded-bins-payload.nix` reads the payload back the way the
minor's runtime does - through `zipfile`, which finds a prefixed archive
by its central directory as `zip.OpenReader` does, or from the tail of
the binary where `stage.go` seeks - and compares it against the
component that was built. Below 1.36 it also greps the binary for an
entry name, because a build that kept `noembedbins` carries an empty
table and would fall back to `PATH` without saying so.

The names are read against `payloadBinaries` in both directions, which
they can be now that the components cover the whole of upstream's list.
A payload entry k0s does not stage is a binary nothing will ever ask
for, and a name k0s stages that the payload lacks is one the node would
have to find on `PATH`.

## What a running node proves

The checks above read the payload out of the binary. They do not say k0s
stages it, or that a staged binary runs, and until every component a
single node needs was in the archive there was no point asking: the rest
would have come off `PATH`, which is a combination upstream neither
ships nor tests.

`checks/source-build-vm.nix` boots a single node on `withPayload` and
asks both. Every binary in the data directory's `bin` is compared
against the component it was built from, and then executed. Running one
is what says it still resolves what it links against; `iptables` is the
case that needs more than `--version`, because its extensions are
dlopened out of the `lib` output and nothing in the ELF names them, so
only an invocation that loads one reaches them.

It reads two lists rather than one, because the payload and what a
single node stages are not the same set. What a node stages is demanded
to be there and to match; the whole payload is what a staged binary has
to appear in. Three entries fall between them: keepalived belongs to the
control plane load balancer, which a single node does not run, kine is
staged for a SQL backend the test does not configure, and konnectivity
is out by mode rather than by configuration - `cmd/controller` gates it
on the node not being a single one.

It runs at every minor. The assembly path was the first reason to expect
a difference, and it is not the only one: `CGO_ENABLED` is 1 at 1.33 and
1.34, so those are the only minors whose k0s binary is dynamically
linked, and each minor stages a different etcd, runc and containerd.
What the check executes is those binaries, so a minor left out is a set
of binaries nothing has run.

The node stays **NotReady**, and the check asserts that rather than
working around it. k0s deploys its CNI, coredns and metrics-server from
`quay.io`, and a test VM resolves nothing, so the kubelet never gets a
cni config. What a registered node does establish is that the API
server, the controller manager, the scheduler, etcd, the kubelet,
containerd and runc all started out of the archive - none of them can
report in otherwise. Reaching Ready needs the images seeded into the VM,
which is not done.
