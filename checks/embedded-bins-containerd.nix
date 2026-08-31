{ lib, pkgs }:
let
  pins = import ../k0s/embedded-bins/pins.nix { inherit lib; };
  components = pkgs.callPackage ../k0s/embedded-bins/components { };

  # containerd 2 moved the module path, and the daemon reports it, so the same
  # binary built from the wrong source says so in the line it prints.
  packageFor =
    version:
    "github.com/containerd/containerd" + lib.optionalString (lib.versionAtLeast version "2") "/v2";

  manifest = map (
    minor:
    let
      component = (pins.read minor).upstream.components.containerd;

      # The same filter the component applies, repeated rather than shared:
      # reading the set the derivation read would make the two agree by
      # construction, and a wrong boundary would then pass here.
      binaries = lib.filter (lib.hasPrefix "containerd") (pins.read minor).upstream.payloadBinaries;
    in
    {
      inherit minor binaries;
      containerd = components.${minor}.containerd;
      inherit (component) version;

      # 1.36 pins a revision and the binary reports it. Below that the pins
      # carry none, and the source is a tarball with no repository to derive
      # one from, so the field is empty by decision rather than by accident.
      revision = component.revision or "";

      # Each shim carries its own copy of the stamps, and the version line above
      # reports the daemon's alone.
      shims = lib.filter (lib.hasPrefix "containerd-shim") binaries;

      package = packageFor component.version;
    }
  ) pins.minors;
in
pkgs.runCommand "k0s-embedded-bins-containerd"
  {
    nativeBuildInputs = [ pkgs.jq ];
    passAsFile = [ "manifest" ];
    manifest = builtins.toJSON manifest;
  }
  ''
    set -o pipefail
    failed=

    run() {
      "$@" 2>&1 || echo "$1 exited $?"
    }

    while read -r entry; do
      eval "$(jq -r '@sh "minor=\(.minor) containerd=\(.containerd) version=\(.version) revision=\(.revision) package=\(.package)"' <<<"$entry")"
      eval "binaries=($(jq -r '@sh "\(.binaries)"' <<<"$entry"))"
      eval "shims=($(jq -r '@sh "\(.shims)"' <<<"$entry"))"

      # The assertions decide, not the exit status: a binary that is missing or
      # refuses to run is a failure to report beside the others rather than one
      # that ends the run and leaves the remaining minors unread.
      report=$(run "$containerd"/bin/containerd --version)
      echo "$minor: $report"

      # The revision is the last field and is empty below 1.36, so the line is
      # matched with the trailing space that leaves rather than trimmed.
      if [ "$report" != "containerd $package v$version $revision" ]; then
        echo "$minor: containerd reports '$report', expected 'containerd $package v$version $revision'" >&2
        failed=1
      fi

      for binary in "''${shims[@]}"; do
        report=$(run "$containerd"/bin/"$binary" -v)
        if ! grep -qxF "  Version:  v$version" <<<"$report"; then
          echo "$minor: $binary reports no 'Version: v$version', got: $report" >&2
          failed=1
        fi
        if ! grep -qxF "  Revision: $revision" <<<"$report"; then
          echo "$minor: $binary reports no 'Revision: $revision', got: $report" >&2
          failed=1
        fi
      done

      # COMMANDS is what keeps ctr and containerd-stress out, and payload.nix
      # takes whatever bin/ holds.
      held=$(ls -A "$containerd"/bin | sort | tr '\n' ' ')
      expected=$(printf '%s\n' "''${binaries[@]}" | sort | tr '\n' ' ')
      if [ "$held" != "$expected" ]; then
        echo "$minor: $containerd/bin holds '$held', expected '$expected'" >&2
        failed=1
      fi
    done < <(jq -c '.[]' "$manifestPath")

    [ -z "$failed" ] || exit 1
    touch $out
  ''
