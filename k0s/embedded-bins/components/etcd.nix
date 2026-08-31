{
  lib,
  fetchFromGitHub,
  etcd_3_5,
  etcd_3_6,
  component,
  sources,
}:
let
  # nixpkgs keeps one package per etcd minor series, and k0s pins 3.5 at k0s
  # 1.33 and 3.6 above it. Selecting on the pin leaves the choice with the data
  # rather than with a second table of k0s minors.
  packaged = {
    "3.5" = etcd_3_5;
    "3.6" = etcd_3_6;
  };
  series = lib.versions.majorMinor component.version;
  etcd = packaged.${series} or (throw "nixpkgs packages no etcd ${series}");

  # The payload stages etcd alone. nixpkgs joins the server with etcdctl and
  # etcdutl, each its own derivation, and only the server is a payload binary.
  etcdserver = etcd.deps.etcdserver;
in
# A nixpkgs bump away from the pin has to say so here: overriding the source
# under a vendor hash built for another version fails much further in.
assert etcdserver.version == component.version;
etcdserver.overrideAttrs (old: {
  src = fetchFromGitHub {
    owner = "etcd-io";
    repo = "etcd";
    tag = "v${component.version}";
    inherit (sources.etcd) hash;
  };

  # nixpkgs stamps the GitSHA and buildGoModule appends -buildid=, so upstream's
  # own flags are added to those rather than put in their place.
  ldflags = old.ldflags ++ lib.splitString " " (import ./go-ldflags.nix component);
})
