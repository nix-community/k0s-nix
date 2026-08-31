# k0s-nix Flake

This repository contains a Nix Flake which provides the necessary utilities to
use `k0s` inside of a NixOS system.


## Status - EXPERIMENTAL

The implementation is in its early phase. It is possible to use and make work
(with a few manual twists) for early inspection.


## Contributions

Both contributions and forks are welcome, also if this should ever reach a state
which could be integrated upstream into Nixpkgs then we would happily archive
this Flake for it.


## Usage

### Build the test system configuration

```sh
nix build .#nixosConfigurations.test.config.system.build.toplevel
```

Inspect the result in `./result`.


### Validate the generated configuration

The module renders `/etc/k0s/k0s.yaml` from `services.k0s.spec`. Build
`validatedConfigFile` in your own flake to have `k0s config validate` run
over the result:

```sh
nix build .#nixosConfigurations.<host>.config.services.k0s.validatedConfigFile
```

The option types reject a malformed value, and k0s reports the combinations
they cannot see:

```
Error: spec: network: calico.mode: Forbidden: dual-stack for calico is only supported for mode `bird`
```

Set `services.k0s.enableConfigCheck = true` to add it to `system.checks`, so
that `nixos-rebuild` fails on an invalid configuration instead of the node
reporting it later. k0s runs the same validation when the controller starts
and refuses to start on an error, so this only moves the failure earlier.

It is off by default because k0s validates against the host as well as the
file, and a build has no host to offer. Control plane load balancing is one
such case; `hostDependentCases` in `checks/config.nix` demonstrates it.

The check is also skipped where the builder cannot execute
`services.k0s.package`, as when cross building.


### Token handling to join the cluster

`k0s` uses a token to join the cluster. The token has to be placed into
`/etc/k0s/k0stoken` (configurable via `services.k0s.tokenFile`), otherwise the
service will not start.

After the join the content is not needed anymore and the file can be emptied.

Providing the token has to be done either manually or by your favorite
automation tooling.


## Known limitations


### `k0s` is included as a binary by default

`k0s`, and the `k0s_1_33` to `k0s_1_36` it aliases, install the release binary
upstream publishes.

A source-built alternative stands beside each of them as `k0s-source_1_33` to
`k0s-source_1_36`. These build k0s from its own source at the same pin and
carry the same payload a release binary carries - containerd, runc, etcd,
kine, konnectivity, kubernetes, iptables and keepalived, each built from the
version `embedded-bins/Makefile.variables` names at that tag. Take one by
naming it:

```nix
services.k0s.package = pkgs.k0s-source_1_36;
```

Nothing caches this flake's outputs, so a consumer of the source build builds
Kubernetes, etcd and containerd itself. That is why the fetched binary remains
what `k0s` resolves to, and why the source build is opted into rather than
defaulted to.

What backs it: [`k0s/README.md`](./k0s/README.md) describes how the payload is
built and attached and
[`components/README.md`](./k0s/embedded-bins/components/README.md) how each
component is packaged, the checks read the version stamps and the payload
contents back out of the built binary on all four minors, and
`checks/source-build-vm.nix` runs a node on it at each of them.

The source build is offered on `x86_64-linux` and `aarch64-linux`, the systems
every component and both assembly paths have been built on. `armv7l-linux` gets
the fetched binary alone. CI builds `x86_64-linux`, so aarch64 is proven by a
run rather than by a job that repeats.

The following pull requests and issues around Nixpkgs are related to this:

- Attempt to add `k0s` 2026-01: https://github.com/NixOS/nixpkgs/pull/479140
- Attempt to package the binary from 2023-10: https://github.com/NixOS/nixpkgs/pull/258846
- Package request issue from 2023-08: https://github.com/NixOS/nixpkgs/issues/247158

## Releases

Every commit on the `main` branch should be considered "stable" and directly usable.
The CI process runs a small, but growing, suite of tests on every pull request before it is merged and cover common use-cases.

Version upgrades to the k0s binary will occur in a relatively timely manner.
The `k0s` nix package attribute will change minor versions from time to time (i.e.: `1.33.x -> 1.34.x`).

Most users can use this flake from its `main` branch. Users that wish to keep a more
stable base can point at a specific commit `sha` instead of the `main` branch,
e.g. in their `flake.nix` file, like so:

```
{
  inputs = {
    k0s-nix.url = "github:nix-community/k0s-nix/cfdbd7ace82d6437aaa9324a53d70cf3521ef22c";
  }
}
```

### Breaking changes

Since there are no releases, changes that need attention when moving a pin forward are noted here.

**2026-08-20, merge commit `63278bd`: the systemd unit is called `k0s` for every role.**

Before this the unit was `k0scontroller` on a controller and `k0sworker` on a worker.
Both are now `k0s`, whatever `services.k0s.role` is set to.
Anything naming the old units has to be updated: `systemctl` invocations, monitoring checks,
and `systemd` drop-ins or ordering dependencies declared in your own configuration.
A `systemd.services.k0scontroller` override in particular no longer reaches the unit, and does not fail.

The switch itself needs no manual step.
`switch-to-configuration` stops the old unit before it starts `k0s.service`,
and neither `containerd` nor `kubelet` survives from the old one;
the switch test on the `unit-rename-evidence` tag covers this.
The k0s process does restart, so the node is briefly unavailable.

## Development and alternatives

Check out the folder [`docs`](./docs). It contains further notes about thoughts
and internals.


## Credit

- The `k0s` package definition took the work from this PR as input:
  <https://github.com/NixOS/nixpkgs/pull/258846>


## Maintainers

- [@johbo](https://github.com/johbo)
- [@plaflamme](https://github.com/plaflamme)


## Contact

- Matrix chat: <https://matrix.to/#/#k0s-nix:matrix.org>


## Pointers

### Projects and Documentation

- [k0s](https://k0sproject.io/)
- [NixOS](https://nixos.org/)
- [Nix Flakes - Wiki](https://nixos.wiki/wiki/Flakes)
- [Nix Flakes - Reference documentation](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html#flake-references)

### Other attempts to bring `k0s` to NixOS

- Packaging request in NixOS - https://github.com/NixOS/nixpkgs/issues/247158
- Pull Request to add the binary `k0s` into Nixpkgs -
  https://github.com/NixOS/nixpkgs/pull/258846
- Systemd unit handling related PR in `k0s` -
  https://github.com/k0sproject/k0s/issues/1318
