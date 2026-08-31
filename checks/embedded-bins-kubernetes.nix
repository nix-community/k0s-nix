{ lib, pkgs }:
let
  pins = import ../k0s/embedded-bins/pins.nix { inherit lib; };
  components = pkgs.callPackage ../k0s/embedded-bins/components { };

  manifest = map (
    minor:
    let
      component = (pins.read minor).upstream.components.kubernetes;

      # The same filter the component applies, repeated rather than shared:
      # reading the set the derivation read would make the two agree by
      # construction, and a wrong boundary would then pass here.
      binaries = lib.filter (lib.hasPrefix "kube") (pins.read minor).upstream.payloadBinaries;
    in
    {
      inherit minor binaries;
      kubernetes = components.${minor}.kubernetes;
      inherit (component) version;
      major = lib.versions.major component.version;

      # Upstream's Dockerfile appends +k0s to the version it stamps, and the
      # binaries report it wherever a node lists its kubelet.
      gitVersion = "v${component.version}+k0s";
      minorVersion = lib.versions.minor component.version;
    }
  ) pins.minors;
in
pkgs.runCommand "k0s-embedded-bins-kubernetes"
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

    expect() {
      local report=$1 field=$2 want=$3
      if ! grep -qF "$field:\"$want\"" <<<"$report"; then
        echo "$minor: $binary reports no $field:\"$want\", got: $report" >&2
        failed=1
      fi
    }

    while read -r entry; do
      eval "$(jq -r '@sh "minor=\(.minor) kubernetes=\(.kubernetes) gitVersion=\(.gitVersion) major=\(.major) minorVersion=\(.minorVersion)"' <<<"$entry")"
      eval "binaries=($(jq -r '@sh "\(.binaries)"' <<<"$entry"))"

      for binary in "''${binaries[@]}"; do
        # --version=raw renders the whole version.Info struct, so one call
        # carries every stamp the build is meant to have set. The assertions
        # decide, not the exit status: a binary that is missing or refuses to
        # run is a failure to report beside the others rather than one that
        # ends the run and leaves the remaining minors unread.
        report=$(run "$kubernetes"/bin/"$binary" --version=raw)

        # GitVersion and GitTreeState are what say the version file was read at
        # all: without it the archive placeholders git-archive substituted into
        # the source win, and they carry the plain version and "archive".
        expect "$report" GitVersion "$gitVersion"
        expect "$report" GitTreeState clean
        expect "$report" Major "$major"
        expect "$report" Minor "$minorVersion"

        # k8s renders this from SOURCE_DATE_EPOCH, and a derivation has no
        # clock: stdenv's own default would stamp 1980 here.
        expect "$report" BuildDate 1970-01-01T00:00:00Z

        # The commit is the source's own, so comparing it against the source
        # would mean unpacking four k8s trees to read one line back. That a
        # commit was stamped is what the version file is on the hook for.
        if ! grep -qE 'GitCommit:"[0-9a-f]{40}"' <<<"$report"; then
          echo "$minor: $binary stamps no commit, got: $report" >&2
          failed=1
        fi
      done
      echo "$minor: $gitVersion, ''${#binaries[@]} binaries"

      # WHAT is what keeps kubectl, kubeadm and the addon manager out, and
      # payload.nix takes whatever bin/ holds.
      held=$(ls -A "$kubernetes"/bin | sort | tr '\n' ' ')
      expected=$(printf '%s\n' "''${binaries[@]}" | sort | tr '\n' ' ')
      if [ "$held" != "$expected" ]; then
        echo "$minor: $kubernetes/bin holds '$held', expected '$expected'" >&2
        failed=1
      fi
    done < <(jq -c '.[]' "$manifestPath")

    [ -z "$failed" ] || exit 1
    touch $out
  ''
