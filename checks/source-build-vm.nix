{
  lib,
  pkgs,
  minor,
}:
let
  components = pkgs.callPackage ../k0s/embedded-bins/components { };
  sourceBuilds = pkgs.callPackage ../k0s/source.nix { };

  k0s = sourceBuilds.withPayload.${minor};
  payload = components.${minor};

  # The payload and what a single node stages are no longer the same set.
  # keepalived belongs to the control plane load balancer, and cplb_linux.go is
  # the only caller that stages it, so a node running no load balancer never
  # asks for it. kine is staged for a SQL backend, and this test configures
  # none. konnectivity is out by mode rather than by configuration:
  # cmd/controller/controller.go gates it on `controllerMode != SingleNodeMode`,
  # and this test runs a single node.
  notStagedBySingleNode = [
    "keepalived"
    "kine"
    "konnectivity"
  ];

  # sha256sum -c reads a name relative to its working directory, so the entries
  # are bare binary names and the check runs from the staging directory.
  # Hashing through stdin keeps the component store paths out of the file,
  # which is what lets it into the VM as plain data.
  hashesOf =
    name: selected:
    pkgs.runCommand "k0s-${name}-${minor}" { } ''
      for component in ${lib.escapeShellArgs (lib.attrValues selected)}; do
        for binary in "$component"/bin/*; do
          echo "$(sha256sum <"$binary" | cut -d' ' -f1)  $(basename "$binary")"
        done
      done >$out
    '';

  stagedHashes = hashesOf "staged-hashes" (removeAttrs payload notStagedBySingleNode);
  payloadHashes = hashesOf "payload-hashes" payload;

  verifyStaged = pkgs.writeShellScript "verify-staged-payload" ''
    set -euo pipefail
    staging=$1
    staged_hashes=$2
    payload_hashes=$3
    cd "$staging"

    # Names and bytes in one pass, driven from the payload's side: a binary the
    # node never staged fails to open, and one staged from somewhere else fails
    # to match. Only what a single node stages is demanded here; the wider list
    # below is what the staging directory is read against.
    sha256sum -c "$staged_hashes"

    for entry in *; do
      # k0s makes the iptables and ip6tables symlinks itself, so those are the
      # entries that belong here without being payload binaries.
      if [ -L "$entry" ]; then
        continue
      fi

      if ! grep -q "  $entry\$" "$payload_hashes"; then
        echo "$entry is staged and is not a payload binary" >&2
        exit 1
      fi

      # Running one is what proves it still resolves what it links against.
      case "$entry" in
        # iptables needs more than a version flag: its extensions are dlopened
        # out of the lib output and nothing in the ELF names them, so only an
        # invocation that loads one reaches them.
        xtables-*-multi) "./$entry" iptables -m conntrack --help >/dev/null ;;
        # containerd 2's shim takes --version and the 1.7 shims below 1.36 do
        # not. Every shim in both majors takes -v.
        containerd-shim*) "./$entry" -v >/dev/null ;;
        *) "./$entry" --version >/dev/null ;;
      esac
    done
  '';
in
pkgs.testers.runNixOSTest {
  name = "k0s-source-build-${minor}";

  nodes.node1 =
    { config, ... }:
    {
      imports = [ ../nixos/k0s.nix ];

      # tests/single.nix stops at `k0s status`, where this one runs the kubelet
      # to registration. A 32-bit guest takes the most qemu will allocate
      # instead, because the assertion guarding that fires at evaluation and
      # would take `nix flake check --all-systems` with it. It reads
      # `memorySize < 2047` where its message says "above 2047", so the ceiling
      # is one lower than the message implies.
      virtualisation = {
        cores = 2;
        diskSize = 8192;
        memorySize = if pkgs.stdenv.hostPlatform.is32bit then 2046 else 4096;
      };

      services.k0s = {
        enable = true;
        role = "single";
        package = k0s;
        spec.api = {
          address = config.networking.primaryIPAddress;
          sans = [ config.networking.primaryIPAddress ];
        };
      };
    };

  testScript =
    { nodes }:
    let
      staging = "${nodes.node1.services.k0s.dataDir}/bin";
    in
    ''
      start_all()
      node1.wait_for_unit("k0s")
      node1.wait_for_file("/run/k0s/status.sock")
      node1.succeed("${k0s}/bin/k0s status")

      # A registered node is what says the control plane and the kubelet came
      # up, and every one of them was staged out of the payload.
      node1.wait_until_succeeds("${k0s}/bin/k0s kubectl get node node1", timeout=300)

      # It stays NotReady on purpose: k0s deploys its CNI from registry images
      # and this VM has no network, so the kubelet never gets a cni config.
      # Asserted rather than left alone, so seeding the images fails this line
      # instead of passing unnoticed.
      node1.succeed(
          "${k0s}/bin/k0s kubectl wait --for=condition=Ready=false --timeout=60s node/node1"
      )

      # Staging is lazy, and iptables is the last of the components k0s reaches
      # for.
      node1.wait_until_succeeds("test -e ${staging}/xtables-nft-multi", timeout=300)
      node1.succeed("${verifyStaged} ${staging} ${stagedHashes} ${payloadHashes}")
    '';
}
