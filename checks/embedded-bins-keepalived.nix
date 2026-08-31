{ lib, pkgs }:
let
  pins = import ../k0s/embedded-bins/pins.nix { inherit lib; };
  components = pkgs.callPackage ../k0s/embedded-bins/components { };

  # The payload carries k0s's feature set rather than nixpkgs', and configure
  # reports what it detected, so the decision is read back out of the binary
  # instead of trusted from the derivation. LVS and VRRP are what k0s's
  # own configuration asks for; the refused names are what nixpkgs' file,
  # libmnl, libnftnl and net-snmp would each have turned on.
  required = [
    "LVS"
    "VRRP"
    "LIBNL3"
  ];
  refused = [
    "IPTABLES"
    "NFTABLES"
    "LIBIPSET"
    "SNMP"
  ];

  manifest = map (minor: {
    inherit minor;
    keepalived = components.${minor}.keepalived;
    inherit ((pins.read minor).upstream.components.keepalived) version;
  }) pins.minors;
in
pkgs.runCommand "k0s-embedded-bins-keepalived"
  {
    nativeBuildInputs = [ pkgs.jq ];
    passAsFile = [ "manifest" ];
    manifest = builtins.toJSON manifest;
  }
  ''
    set -o pipefail
    failed=

    while read -r entry; do
      eval "$(jq -r '@sh "minor=\(.minor) keepalived=\(.keepalived) version=\(.version)"' <<<"$entry")"

      # -v reports on stderr and exits 0.
      report=$("$keepalived"/bin/keepalived -v 2>&1)
      echo "$minor: $(head -1 <<<"$report")"

      # The date comes from the lib/git-commit.h the release tarball ships, and
      # 2.2.8 appends a git commit after it where 2.3.4 does not, so the match
      # stops before both.
      if ! grep -q "^Keepalived v$version (" <<<"$report"; then
        echo "$minor: keepalived reports no 'Keepalived v$version' line" >&2
        failed=1
      fi

      # Config options and System options are two halves of one compiled-in
      # feature set, and which half a name falls in is configure's business.
      # The configure options line above them is not usable here: it names the
      # build environment, which is why the component strips it.
      options=" $(sed -nE 's/^(Config|System) options: +//p' <<<"$report" | tr '\n' ' ')"

      for name in ${lib.escapeShellArgs required}; do
        case "$options" in
          *" $name "*) ;;
          *)
            echo "$minor: keepalived was built without $name" >&2
            failed=1
            ;;
        esac
      done

      # Matched as a prefix, so SNMP covers the four options net-snmp adds and
      # LIBIPSET covers its dynamic variant.
      for name in ${lib.escapeShellArgs refused}; do
        case "$options" in
          *" $name"*)
            echo "$minor: keepalived was built with $name support" >&2
            failed=1
            ;;
        esac
      done

      # payload.nix takes whatever bin/ holds, and the package installs
      # keepalived to sbin and puts a genhash symlink in bin.
      if [ "$(ls -A "$keepalived"/bin)" != keepalived ]; then
        echo "$minor: $keepalived/bin holds more than the keepalived binary" >&2
        failed=1
      fi
    done < <(jq -c '.[]' "$manifestPath")

    [ -z "$failed" ] || exit 1
    touch $out
  ''
