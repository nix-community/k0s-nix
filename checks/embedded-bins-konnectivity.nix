{ lib, pkgs }:
let
  pins = import ../k0s/embedded-bins/pins.nix { inherit lib; };
  components = pkgs.callPackage ../k0s/embedded-bins/components { };

  manifest = map (minor: {
    inherit minor;
    konnectivity = components.${minor}.konnectivity;
    inherit ((pins.read minor).upstream.components.konnectivity) build_go_cgo_enabled;
  }) pins.minors;
in
pkgs.runCommand "k0s-embedded-bins-konnectivity"
  {
    nativeBuildInputs = [
      pkgs.go
      pkgs.jq
    ];
    passAsFile = [ "manifest" ];
    manifest = builtins.toJSON manifest;
  }
  ''
    set -o pipefail
    failed=

    while read -r entry; do
      eval "$(jq -r '@sh "minor=\(.minor) konnectivity=\(.konnectivity) cgo=\(.build_go_cgo_enabled)"' <<<"$entry")"

      binary="$konnectivity"/bin/konnectivity-server

      # The one component that reports no version: upstream stamps none and the
      # server takes no version flag, so there is no line to read back. The Go
      # build info is what the binary does say about itself, and the pinned
      # tarball is tied to its version by the component instead.
      info=$(go version -m "$binary")
      echo "$minor: $(head -1 <<<"$info")"

      # The Dockerfile builds cmd/server/main.go, so this is what says the
      # renamed binary is that command rather than another one in the tree.
      path=$(awk '$1 == "path" { print $2 }' <<<"$info")
      if [ "$path" != sigs.k8s.io/apiserver-network-proxy/cmd/server ]; then
        echo "$minor: the binary was built from $path" >&2
        failed=1
      fi

      settings=$(awk '$1 == "build" { print $2 }' <<<"$info")

      if ! grep -qxF "CGO_ENABLED=$cgo" <<<"$settings"; then
        echo "$minor: the binary was not built with CGO_ENABLED=$cgo" >&2
        failed=1
      fi

      # konnectivity pins no build tags, so one in the binary is one that was
      # invented here.
      if grep -q '^-tags=' <<<"$settings"; then
        echo "$minor: the binary carries build tags the pin does not" >&2
        failed=1
      fi

      # Running it is what says it still resolves what it links against, and
      # --help is as far as the server goes without a cluster to serve. The
      # output is captured rather than piped: grep -q leaves at the first match
      # and the binary takes a SIGPIPE that pipefail then reports as a failure.
      help=$("$binary" --help)
      if ! grep -q 'gRPC proxy server' <<<"$help"; then
        echo "$minor: the binary does not run as the proxy server" >&2
        failed=1
      fi

      # The Dockerfile builds bin/proxy-server and renames it on the way into
      # the image, so the payload entry is the name k0s stages.
      if [ "$(ls -A "$konnectivity"/bin)" != konnectivity-server ]; then
        echo "$minor: $konnectivity/bin is not the renamed binary alone" >&2
        failed=1
      fi
    done < <(jq -c '.[]' "$manifestPath")

    [ -z "$failed" ] || exit 1
    touch $out
  ''
