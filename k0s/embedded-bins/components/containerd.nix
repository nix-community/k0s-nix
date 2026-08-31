{
  lib,
  fetchurl,
  fetchzip,
  containerd,
  component,
  payloadBinaries,
  sources,
}:
let
  # k0s feeds --build-arg CONTAINERD_BINS from a containerd_bins variable that
  # is not one of the _build_* suffixes extract.py reads, so the set is taken
  # from payloadBinaries, which names the same binaries on every packaged minor.
  commands = lib.filter (lib.hasPrefix "containerd") payloadBinaries;

  # Not makeFlags: nixpkgs interpolates that list unquoted, and the tags and the
  # linker flags carry spaces which make would read as targets of their own. The
  # pins also replace nixpkgs' values rather than adding to them, because its
  # list is composed with rec - VERSION and REVISION would keep naming 2.3.3
  # while 1.33 to 1.35 build 1.7.34. The tags are the pin's alone for the same
  # reason, so nixpkgs' no_btrfs is left out.
  #
  # GO_BUILDTAGS takes the pin in either spelling, since both Makefile dialects
  # derive GO_TAGS from it. COMMANDS on the command line also suppresses the
  # `COMMANDS +=` in Makefile.linux, so ctr and containerd-stress stay out.
  # REVISION is passed even where the pin has none, so the Makefile's own
  # git rev-parse never runs in a sandbox with no repository to read.
  makeArgs = lib.escapeShellArgs [
    "PREFIX=${placeholder "out"}"
    "VERSION=v${component.version}"
    "REVISION=${component.revision or ""}"
    "GO_BUILDTAGS=${component.build_go_tags}"
    "SHIM_CGO_ENABLED=${component.build_shim_go_cgo_enabled}"
    "EXTRA_LDFLAGS=${import ./go-ldflags.nix component}"
    "COMMANDS=${toString commands}"
  ];
in
# An upstream rename would leave COMMANDS empty, which installs nothing and
# fails in `install` rather than here.
assert commands != [ ];
(containerd.override { withMan = false; }).overrideAttrs (_: {
  inherit (component) version;

  src = fetchzip { inherit (sources.containerd) url hash; };

  # 1.34 and 1.35 carry an upstream commit that 1.33, on the same containerd
  # version, does not.
  patches = lib.optional (sources ? patch) (fetchurl {
    inherit (sources.patch) url hash;
  });

  # The install below places binaries alone, so nixpkgs' doc output would go
  # unfilled - and a payload component wants bin/ and nothing else anyway.
  outputs = [ "out" ];

  buildPhase = ''
    runHook preBuild
    make ${makeArgs} binaries
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make ${makeArgs} install
    runHook postInstall
  '';
})
