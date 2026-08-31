{ lib, pkgs }:
let
  pins = import ../k0s/embedded-bins/pins.nix { inherit lib; };
  components = pkgs.callPackage ../k0s/embedded-bins/components { };

  manifest = map (minor: {
    inherit minor;
    etcd = components.${minor}.etcd;
    inherit ((pins.read minor).upstream.components.etcd) version;
  }) pins.minors;
in
pkgs.runCommand "k0s-embedded-bins-etcd"
  {
    nativeBuildInputs = [ pkgs.jq ];
    passAsFile = [ "manifest" ];
    manifest = builtins.toJSON manifest;
  }
  ''
    set -o pipefail
    failed=

    while read -r entry; do
      eval "$(jq -r '@sh "minor=\(.minor) etcd=\(.etcd) version=\(.version)"' <<<"$entry")"

      report=$("$etcd"/bin/etcd --version)
      echo "$minor: $(head -1 <<<"$report")"

      if ! grep -qxF "etcd Version: $version" <<<"$report"; then
        echo "$minor: etcd reports no 'etcd Version: $version' line" >&2
        failed=1
      fi

      # Upstream's Dockerfile clones with git and stamps the short SHA. The
      # source here is a tarball with no repository in it, so what is reported
      # is upstream's own no-git fallback - asserted so it stays a decision.
      if ! grep -qxF "Git SHA: GitNotFound" <<<"$report"; then
        echo "$minor: etcd reports a Git SHA, so the source grew a repository" >&2
        failed=1
      fi

      # nixpkgs joins the server with etcdctl and etcdutl. payload.nix takes
      # whatever bin/ holds, so the join reaching the payload would stage two
      # binaries k0s never asks for.
      if [ "$(ls -A "$etcd"/bin)" != etcd ]; then
        echo "$minor: $etcd/bin holds more than the server binary" >&2
        failed=1
      fi
    done < <(jq -c '.[]' "$manifestPath")

    [ -z "$failed" ] || exit 1
    touch $out
  ''
