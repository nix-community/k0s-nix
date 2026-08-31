{
  lib,
  fetchzip,
  kubernetes,
  runtimeShell,
  component,
  payloadBinaries,
  sources,
}:
let
  # k0s feeds --build-arg KUBERNETES_BINS from a kubernetes_bins variable that
  # is not one of the _build_* suffixes extract.py reads, so the set is taken
  # from payloadBinaries, which names the same four on every packaged minor.
  commands = lib.filter (lib.hasPrefix "kube") payloadBinaries;

  inherit (component) version;
in
# An upstream rename would leave WHAT empty, which builds nothing and fails in
# the install rather than here.
assert commands != [ ];
(kubernetes.override { components = map (name: "cmd/${name}") commands; }).overrideAttrs (_: {
  inherit version;

  src = fetchzip { inherit (sources.kubernetes) url hash; };

  # nixpkgs patches the addon manager's lib path, and the addon manager is not
  # one of the payload binaries.
  patches = [ ];

  # The install below places the payload binaries alone, so nixpkgs' man and
  # pause outputs would go unfilled - and a payload component wants bin/ and
  # nothing else anyway.
  outputs = [ "out" ];

  buildPhase = ''
    runHook preBuild
    patchShebangs ./hack

    # k8s renders buildDate from SOURCE_DATE_EPOCH, and a derivation has no
    # clock. source.nix stamps 1970-01-01T00:00:00Z into k0s itself, and this
    # is the same constant. It is exported here rather than set on the
    # derivation because set-source-date-epoch-to-latest.sh raises the variable
    # to the newest mtime under sourceRoot after unpacking, and a store path
    # carries mtime 1 - so a value set any earlier comes out a second late.
    export SOURCE_DATE_EPOCH=0

    # k8s takes its stamps from git, and the source is a GitHub archive whose
    # placeholders git-archive has already substituted. hack/lib/version.sh
    # reads those before it looks at the environment and overwrites what it
    # finds, so upstream's exported KUBE_GIT_VERSION never survives here - its
    # Dockerfile only gets away with it because it clones. A version file is
    # read ahead of both, and carries the whole stamp.
    commit=$(sed -n "s/^ *KUBE_GIT_COMMIT='\([0-9a-f]\{40\}\)'$/\1/p" hack/lib/version.sh)
    [ -n "$commit" ] || {
      echo "hack/lib/version.sh carries no archive commit stamp" >&2
      exit 1
    }

    # The version below is stamped rather than read, so no binary can report a
    # source that is not the pinned one - a pin moved without its fetch entry
    # would ship binaries claiming a version nobody built. The archive stamp
    # names the tag it was cut from, which is what ties the two together.
    tag=$(sed -n "/^ *if \[\[ '/s/.*tag: \(v[^ ,']*\).*/\1/p" hack/lib/version.sh)
    [ "$tag" = "v${version}" ] || {
      echo "the source archive is tagged '$tag', and the pin says 'v${version}'" >&2
      exit 1
    }

    cat >kube-version <<EOF
    KUBE_GIT_COMMIT='$commit'
    KUBE_GIT_TREE_STATE='clean'
    KUBE_GIT_VERSION='v${version}+k0s'
    KUBE_GIT_MAJOR='${lib.versions.major version}'
    KUBE_GIT_MINOR='${lib.versions.minor version}'
    EOF
    export KUBE_GIT_VERSION_FILE=$PWD/kube-version

    make SHELL=${runtimeShell} WHAT="$WHAT" \
      GOFLAGS="${component.build_go_flags} -tags=${component.build_go_tags}" \
      GOLDFLAGS="${import ./go-ldflags.nix component}"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    for target in $WHAT; do
      install -D _output/local/go/bin/''${target##*/} -t $out/bin
    done
    runHook postInstall
  '';
})
