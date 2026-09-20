{
  version = "1.35.8+k0s.1";
  srcs = {
    armv7l-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.35.8+k0s.1/k0s-v1.35.8+k0s.1-arm";
      hash = "sha256-Ww5c8KdQPSbbsDTLd64gw/COKKYNEd8oYAsIShoSJVQ=";
    };
    aarch64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.35.8+k0s.1/k0s-v1.35.8+k0s.1-arm64";
      hash = "sha256-dqke/vOvOgzUIUxU0E2y4L49oNITbixfQ0vzFGAx0i0=";
    };
    x86_64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.35.8+k0s.1/k0s-v1.35.8+k0s.1-amd64";
      hash = "sha256-CeXFuboKYhj+Rtr955nM1iJw+D/lw+ppW+sbQJi67Wc=";
    };
  };
}
