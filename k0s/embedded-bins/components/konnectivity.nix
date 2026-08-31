{
  lib,
  buildGoModule,
  fetchzip,
  component,
  sources,
}:
let
  inherit (component) version;
in
# -a rebuilds packages that are already built, which buys nothing in a sandbox
# that has built none. Dropping it holds only while it is all the pin carries.
assert component.build_go_flags == "-a";
# Upstream stamps no version and the server has no version flag, so nothing can
# be read back out of the binary. The tarball's own name is what ties a minor to
# the version it records, and this is the only place that can say so.
assert lib.hasSuffix "/v${version}.tar.gz" sources.konnectivity.url;
buildGoModule {
  pname = "konnectivity-server";
  inherit version;

  # Upstream's Dockerfile runs `make gen` before it builds, which is protoc and
  # mockgen installed over the network. Everything the two write is committed in
  # the tarball - the .pb.go files and proto/agent/mocks - so the build reads
  # them from the source and the generators never run.
  src = fetchzip { inherit (sources.konnectivity) url hash; };

  # The tarball carries vendor/, so there is no module fetch and no hash to
  # record per version - the one thing every other Go component here owes.
  vendorHash = null;

  subPackages = [ "cmd/server" ];

  env.CGO_ENABLED = component.build_go_cgo_enabled;

  ldflags = lib.splitString " " (import ./go-ldflags.nix component);

  # checkPhase runs over subPackages, and cmd/server carries no test files, so
  # leaving it on would report a suite that was never there. What tests the
  # repository has sit in packages this does not build.
  doCheck = false;

  # The Dockerfile builds bin/proxy-server and renames it on the way into the
  # image. The payload entry has to be the name k0s stages.
  postInstall = ''
    mv $out/bin/server $out/bin/konnectivity-server
  '';

  meta = {
    description = "Konnectivity server, the API server network proxy";
    homepage = "https://github.com/kubernetes-sigs/apiserver-network-proxy";
    license = lib.licenses.asl20;
    mainProgram = "konnectivity-server";
    platforms = lib.platforms.linux;
  };
}
