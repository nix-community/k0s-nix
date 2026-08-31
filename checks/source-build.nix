{ lib, pkgs }:
let
  pins = import ../k0s/embedded-bins/pins.nix { inherit lib; };
  sourceBuilds = pkgs.callPackage ../k0s/source.nix { };

  manifest = map (
    minor:
    let
      pin = pins.read minor;
      component = pin.upstream.components;
    in
    {
      inherit minor;
      k0s = sourceBuilds.bare.${minor};

      # The field names are the ones `k0s version --json` prints, and every one
      # of them is `omitempty` - so a stamp that did not take drops out of the
      # report rather than reading as an empty string.
      expected = {
        k0s = "v${pin.k0sVersion}";
        runc = component.runc.version;
        containerd = component.containerd.version;
        kubernetes = component.kubernetes.version;
        kine = component.kine.version;
        etcd = component.etcd.version;
        konnectivity = component.konnectivity.version;
      };
    }
  ) pins.minors;
in
pkgs.runCommand "k0s-source-build"
  {
    nativeBuildInputs = [ pkgs.jq ];
    passAsFile = [ "manifest" ];
    manifest = builtins.toJSON manifest;
  }
  ''
    set -o pipefail
    failed=

    while read -r entry; do
      eval "$(jq -r '@sh "minor=\(.minor) k0s=\(.k0s)"' <<<"$entry")"
      expected=$(jq -Sc .expected <<<"$entry")

      reported=$("$k0s"/bin/k0s version --json | jq -Sc .)
      echo "$minor: $reported"

      if [ "$reported" != "$expected" ]; then
        echo "$minor: expected $expected" >&2
        failed=1
      fi
    done < <(jq -c '.[]' "$manifestPath")

    [ -z "$failed" ] || exit 1
    touch $out
  ''
