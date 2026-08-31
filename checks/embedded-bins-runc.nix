{ lib, pkgs }:
let
  pins = import ../k0s/embedded-bins/pins.nix { inherit lib; };
  components = pkgs.callPackage ../k0s/embedded-bins/components { };

  manifest = map (
    minor:
    let
      component = (pins.read minor).upstream.components.runc;
    in
    {
      inherit minor;
      runc = components.${minor}.runc;
      inherit (component) version;
      libseccomp = component.argpin_LIBSECCOMP_VERSION;
    }
  ) pins.minors;
in
pkgs.runCommand "k0s-embedded-bins-runc"
  {
    nativeBuildInputs = [ pkgs.jq ];
    passAsFile = [ "manifest" ];
    manifest = builtins.toJSON manifest;
  }
  ''
    set -o pipefail
    failed=

    while read -r entry; do
      eval "$(jq -r '@sh "minor=\(.minor) runc=\(.runc) version=\(.version) libseccomp=\(.libseccomp)"' <<<"$entry")"

      report=$("$runc"/bin/runc --version)
      echo "$minor: $(tr '\n' ' ' <<<"$report")"

      # runc reports the libseccomp it linked against, which is the only thing
      # that distinguishes the pinned build from the nixpkgs package.
      for expected in "runc version $version" "libseccomp: $libseccomp"; do
        if ! grep -qxF "$expected" <<<"$report"; then
          echo "$minor: runc reports no '$expected' line" >&2
          failed=1
        fi
      done

      if [ "$("$runc"/bin/runc features | jq -r .linux.seccomp.enabled)" != true ]; then
        echo "$minor: the seccomp build tag did not take" >&2
        failed=1
      fi

      # The payload carries this binary itself, so a wrapper exec'ing a store
      # path would defeat vendoring it.
      if [ "$(ls -A "$runc"/bin)" != runc ]; then
        echo "$minor: $runc/bin holds more than the binary, so it is wrapped" >&2
        failed=1
      fi
    done < <(jq -c '.[]' "$manifestPath")

    [ -z "$failed" ] || exit 1
    touch $out
  ''
