{
  lib,
  fetchzip,
  keepalived,
  libnl,
  openssl,
  pkg-config,
  removeReferencesTo,
  runCommand,
  component,
  sources,
}:
# The payload drops upstream's static linking, for the reasons README.md gives,
# and -s only strips, which fixupPhase does anyway. Anything else here would be
# a pin dropped in silence.
assert component.build_cflags == "-static -s";
assert component.build_ldflags == "-static";
let
  # nixpkgs carries 2.3.4, which is the pin at every minor but 1.33. Overriding
  # on all of them rather than only where they differ keeps one path in play
  # instead of two that diverge as the pins move.
  #
  # The release tarball ships lib/git-commit.h with the date the version string
  # reports, where the GitHub archive nixpkgs fetches has none and
  # lib/Makefile.am derives one from the newest file mtime - which is 1 in a
  # store path. autoreconfHook goes with it: the tarball carries configure, and
  # upstream's Dockerfile runs it directly.
  pinned = keepalived.overrideAttrs (_: {
    inherit (component) version;
    src = fetchzip { inherit (sources.keepalived) url hash; };

    # k0s's feature set rather than nixpkgs', which is what dropping file,
    # libmnl, libnftnl and net-snmp here amounts to.
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [
      libnl
      openssl
    ];
    configureFlags = lib.splitString " " component.build_configure_flags;
  });
in
# keepalived installs to sbin and puts a genhash symlink in bin, and payload.nix
# takes whatever bin/ holds.
runCommand "keepalived-payload-${component.version}"
  {
    nativeBuildInputs = [ removeReferencesTo ];
  }
  ''
    install -Dm755 ${pinned}/sbin/keepalived $out/bin/keepalived

    # configure compiles its own command line into the binary, so the package's
    # prefix and the pkg-config path of every buildInput's dev output are
    # strings in it. payload-closure would then carry a node the build
    # environment of a binary it already has. The dev outputs are the whole of
    # PKG_CONFIG_PATH because buildInputs above is, and what the prefix costs is
    # the default configuration path - which k0s never reaches, since it always
    # passes --use-file.
    remove-references-to \
      -t ${pinned} -t ${lib.getDev openssl} -t ${lib.getDev libnl} \
      $out/bin/keepalived
  ''
