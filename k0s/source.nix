{
  lib,
  buildGoModule,
  callPackage,
  fetchzip,
  makeWrapper,
  runCommand,
  util-linuxMinimal,
}:
let
  pins = import ./embedded-bins/pins.nix { inherit lib; };
  components = callPackage ./embedded-bins/components { };
  mkPayload = callPackage ./embedded-bins/payload.nix { };

  # 1.36 moved the payload from an offset table generated into the binary to a
  # zip appended behind it.
  hasZipPayload = minor: lib.versionAtLeast (pins.read minor).k0sVersion "1.36";

  # Keyed by k0s version rather than by minor, so a moved pin reads as a
  # missing entry - which is what lets update.py see that it owes a hash.
  # Refreshed by update.py, which takes the hash from the fixed-output
  # derivation it makes fail.
  vendorHashes = {
    "1.33.13+k0s.1" = "sha256-t31v/A4EsaPph1QOd/0h3qTfL5poItP6k2ULLqCMEms=";
    "1.34.11+k0s.0" = "sha256-ChF7+6tH43TuFSSm/Y8gUei8Ha28BlzSl1pl5ITziKE=";
    "1.35.7+k0s.0" = "sha256-AfAtrHoMdAbVoloNvj/785uy8Pa1PrlOCfEh2iEA8u4=";
    "1.36.3+k0s.2" = "sha256-+ZME6rqB0GU6cKCPB3KgxgHyUN5QnmcIW8UgLsER5G8=";
  };

  # Kept by hand and checked against the extracted value rather than read from
  # it, so upstream changing this stops the build and is looked at.
  cgoEnabled = {
    "1_33" = 1;
    "1_34" = 1;
    "1_35" = 0;
    "1_36" = 0;
  };

  # k0s has no clock, and upstream derives BUILD_DATE from the last commit date,
  # falling back to the wall clock when there is no git - which a fetched
  # tarball never has. A constant is what keeps the build reproducible; nixpkgs'
  # k3s stamps one for the same reason.
  buildDate = "1970-01-01T00:00:00Z";

  buildPkg = "github.com/k0sproject/k0s/pkg/build";
  componentBase = "k8s.io/component-base/version";

  # At 1.36 payload is always null: the zip is appended to the finished binary
  # and the Go build never learns of it. Below 1.36 the components are gzipped
  # into one blob and hack/gen-bindata generates the offset table that locates
  # them, which the build compiles in - so they have to be here.
  buildK0s =
    minor: payload:
    let
      pin = pins.read minor;
      component = pin.upstream.components;
      kubernetesVersion = component.kubernetes.version;

      # Below 1.36 a build without the generated table needs the noembedbins tag
      # to compile at all, and containerd's stamp still lives on the pre-v2
      # module path.
      zipPayload = hasZipPayload minor;
      containerdVersionPkg =
        if zipPayload then
          "github.com/containerd/containerd/v2/version"
        else
          "github.com/containerd/containerd/version";

      generateBindata = payload != null;
      staging = "embedded-bins/staging/linux";

      recordedCgo = cgoEnabled.${minor} or (throw "no CGO_ENABLED recorded for ${minor}");
      upstreamCgo = pin.upstream.k0sBinary.env.CGO_ENABLED;
      checkedCgo = lib.throwIf (toString recordedCgo != upstreamCgo) ''
        k0s ${pin.k0sVersion} builds with CGO_ENABLED=${upstreamCgo} upstream,
        ${toString recordedCgo} is recorded in k0s/source.nix
      '' recordedCgo;
    in
    buildGoModule {
      pname = "k0s";
      version = pin.k0sVersion;

      src = fetchzip { inherit (pins.fetch minor "k0s") url hash; };

      vendorHash =
        vendorHashes.${pin.k0sVersion} or (throw "no vendorHash recorded for k0s ${pin.k0sVersion}");

      # No codegen phase. The Makefile regenerates deepcopy functions, CRDs and
      # the clientset before every build, because the stamp files it uses as
      # targets are not tracked - the generated sources themselves are. Each
      # generator runs through `go run <tool>@<version>`, which wants the
      # network, so go build is both sufficient here and the only option.
      subPackages = [ "." ];

      # The offset table and the blob it describes come out of one generator
      # run, so the table is compiled in here and the blob leaves through a
      # second output, to be appended once the package is finished.
      outputs = [ "out" ] ++ lib.optional generateBindata "bindata";

      preBuild = lib.optionalString generateBindata ''
        mkdir -p ${staging}/bin
        for component in ${lib.escapeShellArgs payload}; do
          install -m755 -t ${staging}/bin "$component"/bin/*
        done

        go run -tags=hack ./hack/gen-bindata/cmd \
          -o bindata_linux -pkg assets \
          -gofile pkg/assets/zz_generated_offsets_linux.go \
          -prefix ${staging}/ ${staging}/bin
      '';

      postInstall = lib.optionalString generateBindata ''
        install -Dm644 -t $bindata \
          bindata_linux pkg/assets/zz_generated_offsets_linux.go
      '';

      # preBuild is inherited by the vendor derivation, where the generator
      # runs before `go mod vendor` writes the tree it needs - and nothing
      # notices until a vendorHash is recomputed.
      overrideModAttrs = _: _: { preBuild = ""; };

      env.CGO_ENABLED = checkedCgo;

      tags = [ "osusergo" ] ++ lib.optional (!zipPayload && !generateBindata) "noembedbins";

      # Upstream's -extldflags=-static is deliberately absent: inert where cgo
      # is off, and where it is on it is the same decision the component
      # derivations take, since nixpkgs ships no static libc to link against.
      ldflags = [
        "-w"
        "-s"
        "-X ${buildPkg}.Version=v${pin.k0sVersion}"
        "-X ${buildPkg}.RuncVersion=${component.runc.version}"
        "-X ${buildPkg}.ContainerdVersion=${component.containerd.version}"
        "-X ${buildPkg}.KubernetesVersion=${kubernetesVersion}"
        "-X ${buildPkg}.KineVersion=${component.kine.version}"
        "-X ${buildPkg}.EtcdVersion=${component.etcd.version}"
        "-X ${buildPkg}.KonnectivityVersion=${component.konnectivity.version}"
        "-X ${componentBase}.gitVersion=v${kubernetesVersion}"
        "-X ${componentBase}.gitMajor=${lib.versions.major kubernetesVersion}"
        "-X ${componentBase}.gitMinor=${lib.versions.minor kubernetesVersion}"
        "-X ${componentBase}.gitCommit=not_available"
        "-X ${componentBase}.buildDate=${buildDate}"
        "-X ${containerdVersionPkg}.Version=${component.containerd.version}"
      ]
      # Below 1.36 upstream reads this out of the staged containerd binary, and
      # only when it built a payload at all, so a payload-less build has nothing
      # to read and upstream's own leaves it empty too.
      ++ lib.optional zipPayload "-X ${containerdVersionPkg}.Revision=${component.containerd.revision}";

      # The suite wants a cluster, a container runtime and root for a good part
      # of itself. What this package has to get right is the binary's identity,
      # and checks/source-build.nix asserts that instead.
      doCheck = false;

      meta = {
        description = "k0s - The Zero Friction Kubernetes, built from source";
        homepage = "https://k0sproject.io";
        license = lib.licenses.asl20;
        mainProgram = "k0s";
        platforms = import ./source-systems.nix;
      };
    };

  # k0s reads its payload out of its own executable, which a wrapper is not:
  # os.Executable() resolves to whatever the wrapper execs. So the real binary
  # sits at libexec/k0s, where a payload can be appended to it, and bin/k0s is
  # the wrapper.
  #
  # util-linux is a host tool k0s expects to find rather than something it
  # carries. No payload component is put on PATH to stand in for the archive,
  # because staging one out of nixpkgs would run a combination nobody ships.
  #
  # The payload is attached here rather than in the Go build because fixupPhase
  # strips $out/bin and shrinks its RPATHs, and both rewrite the ELF - which
  # would discard whatever sits behind it.
  assemble =
    {
      staged ? [ ],
      payload ? null,
      offsets ? null,
    }:
    k0s:
    runCommand k0s.name
      {
        nativeBuildInputs = [ makeWrapper ];
        inherit (k0s) meta;
        passthru = { inherit payload offsets; };
      }
      ''
        install -Dm755 ${k0s}/bin/k0s $out/libexec/k0s
        ${lib.optionalString (payload != null) "cat ${payload} >>$out/libexec/k0s"}
        makeWrapper $out/libexec/k0s $out/bin/k0s \
          --prefix PATH : ${lib.makeBinPath [ util-linuxMinimal ]}

        # A component is compressed into the payload, so its store path is
        # nowhere the reference scanner would find it and a collection would
        # take what the staged binaries link against. Naming the paths in the
        # output is what holds their closures.
        ${lib.optionalString (staged != [ ]) ''
          mkdir -p $out/nix-support
          printf '%s\n' ${lib.escapeShellArgs staged} >$out/nix-support/payload-closure
        ''}
      '';

  loaded =
    minor:
    let
      staged = lib.attrValues components.${minor};
    in
    if hasZipPayload minor then
      assemble {
        inherit staged;
        payload = mkPayload (pins.read minor).k0sVersion staged;
      } (buildK0s minor null)
    else
      let
        k0s = buildK0s minor staged;
      in
      assemble {
        inherit staged;
        payload = "${k0s.bindata}/bindata_linux";
        offsets = "${k0s.bindata}/zz_generated_offsets_linux.go";
      } k0s;
in
{
  bare = lib.genAttrs pins.minors (minor: assemble { } (buildK0s minor null));
  withPayload = lib.genAttrs pins.minors loaded;
}
