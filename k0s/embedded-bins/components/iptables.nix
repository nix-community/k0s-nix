{
  fetchzip,
  iptables,
  runCommand,
  component,
  sources,
}:
let
  # k0s pins 1.8.11 below 1.36 and 1.8.13 at it, and nixpkgs carries the latter.
  # Overriding on every minor rather than only where they differ keeps one path
  # in play instead of two that diverge as the pins move.
  pinned = iptables.overrideAttrs (_: {
    inherit (component) version;
    src = fetchzip { inherit (sources.iptables) url hash; };
  });
in
# Upstream links these statically, which the payload does not reproduce for the
# reasons README.md gives; the flags are in the Dockerfile's own configure call
# rather than in a pin, so there is nothing here for a guard to assert against.
#
# k0s stages both multi binaries and makes the iptables and ip6tables symlinks
# itself, so the payload carries those two out of the forty-odd entries the
# nixpkgs package installs.
runCommand "iptables-payload-${component.version}" { } ''
  install -Dm755 -t $out/bin \
    ${pinned}/bin/xtables-legacy-multi \
    ${pinned}/bin/xtables-nft-multi
''
