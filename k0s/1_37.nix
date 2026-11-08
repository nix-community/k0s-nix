{
  version = "1.37.2+k0s.1";
  srcs = {
    armv7l-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.37.2+k0s.1/k0s-v1.37.2+k0s.1-arm";
      hash = "sha256-sl5fjliaNsacAn/qBPvEH2KJP9WPgblXCmCIC5ux5uA=";
    };
    aarch64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.37.2+k0s.1/k0s-v1.37.2+k0s.1-arm64";
      hash = "sha256-0EQmBB75rAArlX+/Q/w23XNjmBR9t1ifrVNod1O+3VI=";
    };
    x86_64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.37.2+k0s.1/k0s-v1.37.2+k0s.1-amd64";
      hash = "sha256-R3DPif9F5DKSgZ9uOgKiWkU7x1DHd/b3rS3jNfP0HfU=";
    };
  };
}
