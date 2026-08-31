{ lib, pkgs }:
let
  pins = import ../k0s/embedded-bins/pins.nix { inherit lib; };
  components = pkgs.callPackage ../k0s/embedded-bins/components { };

  manifest = map (minor: {
    inherit minor;
    kine = components.${minor}.kine;
    inherit ((pins.read minor).upstream.components.kine) version;
  }) pins.minors;
in
pkgs.runCommand "k0s-embedded-bins-kine"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.patchelf
    ];
    passAsFile = [ "manifest" ];
    manifest = builtins.toJSON manifest;
  }
  ''
    set -o pipefail
    failed=

    while read -r entry; do
      eval "$(jq -r '@sh "minor=\(.minor) kine=\(.kine) version=\(.version)"' <<<"$entry")"

      # Both stamps are in the one line: upstream builds GitCommit from a clone,
      # and a tarball has no repository to read one out of.
      report=$("$kine"/bin/kine --version)
      echo "$minor: $report"
      if [ "$report" != "kine version v$version (unknown)" ]; then
        echo "$minor: expected 'kine version v$version (unknown)'" >&2
        failed=1
      fi

      # The nats tag is what compiles the embedded server in, and its
      # constructor is the symbol the linker then keeps. The driver itself is
      # built either way, so the nats-io module being referenced proves nothing.
      if ! grep -qa 'nats-server/v2/server\.NewServer' "$kine"/bin/kine; then
        echo "$minor: the nats build tag did not take" >&2
        failed=1
      fi

      # cgo off leaves go-sqlite3 a stub that compiles and fails at runtime, and
      # a Go binary that links no C carries no interpreter.
      if ! patchelf --print-interpreter "$kine"/bin/kine >/dev/null; then
        echo "$minor: kine links nothing, so it was built without cgo" >&2
        failed=1
      fi

      if [ "$(ls -A "$kine"/bin)" != kine ]; then
        echo "$minor: $kine/bin holds more than the kine binary" >&2
        failed=1
      fi
    done < <(jq -c '.[]' "$manifestPath")

    [ -z "$failed" ] || exit 1
    touch $out
  ''
