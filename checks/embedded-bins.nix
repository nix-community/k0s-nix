{ lib, pkgs }:
let
  extractor = ../k0s/embedded-bins;
  pins = import (extractor + "/pins.nix") { inherit lib; };
  inherit (pins) minors;

  source = minor: pkgs.fetchzip { inherit (pins.fetch minor "k0s") url hash; };

  # The release-binary package and the source data are updated by separate
  # scripts on purpose, so the version they each name has to be compared
  # rather than assumed to agree.
  manifest = map (minor: {
    inherit minor;
    source = source minor;
    recorded = (pins.read minor).k0sVersion;
    declared = (import (../k0s + "/${minor}.nix")).version;
  }) minors;
in
pkgs.runCommand "k0s-embedded-bins-extraction"
  {
    nativeBuildInputs = [
      pkgs.gnumake
      pkgs.jq
      pkgs.python3
    ];
    passAsFile = [ "manifest" ];
    manifest = builtins.toJSON manifest;
  }
  ''
    set -o pipefail
    failed=

    extract() {
      python3 ${extractor}/extract.py "$1"
    }

    while read -r entry; do
      eval "$(jq -r '@sh "minor=\(.minor) source=\(.source) recorded=\(.recorded) declared=\(.declared)"' <<<"$entry")"

      if [ "$recorded" != "$declared" ]; then
        echo "$minor: k0s/$minor.nix declares $declared, the embedded-bins data records $recorded" >&2
        failed=1
        continue
      fi

      if ! diff --unified --label recorded --label extracted \
        <(jq -S .upstream "${extractor}/$minor.json") \
        <(extract "$source" | jq -S .); then
        echo "$minor: the recorded data does not match what $declared actually pins" >&2
        failed=1
      fi
    done < <(jq -c '.[]' "$manifestPath")

    # The guards are what make an update stop rather than silently drop
    # something upstream added, so they are exercised rather than trusted.
    # One source serves: the known sets are shared across the minors.
    reference=${source (lib.last minors)}
    work=$(mktemp -d)

    mutate() {
      rm -rf "$work/src"
      cp -r --no-preserve=mode,ownership "$reference" "$work/src"
    }

    refuses() {
      if extract "$work/src" >/dev/null 2>"$work/message"; then
        echo "the extractor accepted $1" >&2
        failed=1
      else
        echo "refused $1: $(cat "$work/message")"
      fi
    }

    mutate
    mkdir -p "$work/src/embedded-bins/newcomponent"
    touch "$work/src/embedded-bins/newcomponent/Dockerfile"
    refuses "a new component directory"

    mutate
    printf '\t  --build-arg NEW_FLAG=$(patsubst %%/Dockerfile,%%,$<)_build_new_flag\n' \
      >>"$work/src/embedded-bins/Makefile"
    refuses "a new build parameter suffix"

    mutate
    echo 'ARG NEW_PIN=1' >>"$work/src/embedded-bins/runc/Dockerfile"
    refuses "a new Dockerfile ARG default"

    mutate
    sed -i '/$(GO) build $(BUILD_GO_FLAGS)/d' "$work/src/Makefile"
    refuses "a k0s Makefile that builds the binary some other way"

    [ -z "$failed" ] || exit 1
    touch $out
  ''
