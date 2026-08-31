{
  lib,
  fetchzip,
  kine,
  component,
  sources,
}:
let
  versionPkg = "github.com/k3s-io/kine/pkg/version";

  # Keyed by kine version rather than by k0s minor, since 1.34 and 1.35 pin the
  # same one. Refreshed when a pin moves: build the component and take the hash
  # the failing fixed-output derivation reports.
  vendorHashes = {
    "0.13.19" = "sha256-1Dwu1b6y1ibGt7w6Iu3lKWItwVn9H/TQFbTL2z2rVoc=";
    "0.14.16" = "sha256-RFqK2k1Gm89Oc3c+LAEE2FyOVIfEYIrEbUXQVHUWbrU=";
    "0.16.3" = "sha256-8AWGYrnawnPnAqGr8pDzh6ePzyuY5Q5fy4cdphYELB8=";
  };

  inherit (component) version;
in
# Both are commented out in Makefile.variables, so the Dockerfile passes them
# empty and cgo defaults to on, which the sqlite driver needs. Either being
# uncommented is a pin this component would otherwise drop in silence.
assert !(component ? build_go_cgo_enabled);
assert !(component ? build_go_flags);
kine.overrideAttrs (old: {
  inherit version;

  src = fetchzip { inherit (sources.kine) url hash; };

  vendorHash = vendorHashes.${version} or (throw "no vendorHash recorded for kine ${version}");

  tags = lib.splitString "," component.build_go_tags;

  # The list replaces nixpkgs' rather than being added to it: its stamps name
  # the version it packages, and a second -X on the same symbol would leave the
  # identity to whichever the linker takes last. GitCommit is upstream's
  # `git rev-parse` on a clone, and a tarball has no repository - so nixpkgs'
  # own answer is kept, and the check reads it back.
  ldflags = lib.splitString " " (import ./go-ldflags.nix component) ++ [
    "-X ${versionPkg}.Version=v${version}"
    "-X ${versionPkg}.GitCommit=unknown"
  ];

  # nixpkgs sets DBSTAT_VTAB on every version and only 1.33 pins it, so the pin
  # replaces the value instead of adding to it.
  env = old.env // {
    CGO_CFLAGS = component.build_go_cgo_cflags;
  };

  # The nats tag compiles a suite nixpkgs never runs, and at 0.13.19 it fails
  # against its own embedded server, a different set of tests each run.
  doCheck = false;
})
