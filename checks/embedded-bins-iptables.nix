{ lib, pkgs }:
let
  pins = import ../k0s/embedded-bins/pins.nix { inherit lib; };
  components = pkgs.callPackage ../k0s/embedded-bins/components { };

  # k0s stages both and errors if either is missing, then symlinks iptables and
  # ip6tables to whichever mode it detects. Each names its own backend in the
  # version line, which is what tells the two builds apart.
  modes = {
    xtables-legacy-multi = "legacy";
    xtables-nft-multi = "nf_tables";
  };

  manifest = map (minor: {
    inherit minor;
    iptables = components.${minor}.iptables;
    inherit ((pins.read minor).upstream.components.iptables) version;
  }) pins.minors;
in
pkgs.runCommand "k0s-embedded-bins-iptables"
  {
    nativeBuildInputs = [ pkgs.jq ];
    passAsFile = [ "manifest" ];
    manifest = builtins.toJSON manifest;
  }
  ''
    set -o pipefail
    failed=

    while read -r entry; do
      eval "$(jq -r '@sh "minor=\(.minor) iptables=\(.iptables) version=\(.version)"' <<<"$entry")"

      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (binary: backend: ''
          report=$("$iptables"/bin/${binary} iptables --version)
          echo "$minor: $report"
          if [ "$report" != "iptables v$version (${backend})" ]; then
            echo "$minor: ${binary} reports '$report', expected iptables v$version (${backend})" >&2
            failed=1
          fi

          # The extensions are shared objects here rather than compiled in the
          # way upstream's static build has them, so the payload binary dlopens
          # them out of the store and the store has to still hold them.
          if ! "$iptables"/bin/${binary} iptables -m conntrack --help >/dev/null 2>&1; then
            echo "$minor: ${binary} cannot load the conntrack extension" >&2
            failed=1
          fi
        '') modes
      )}

      # payload.nix takes whatever bin/ holds, and the nixpkgs package installs
      # some forty entries around these two.
      if [ "$(ls -A "$iptables"/bin | sort | tr '\n' ' ')" != "${lib.concatStringsSep " " (lib.attrNames modes)} " ]; then
        echo "$minor: $iptables/bin holds more than the two multi binaries" >&2
        failed=1
      fi
    done < <(jq -c '.[]' "$manifestPath")

    [ -z "$failed" ] || exit 1
    touch $out
  ''
