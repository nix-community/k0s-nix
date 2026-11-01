{
  version = "1.37.1+k0s.0";
  srcs = {
    armv7l-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.37.1+k0s.0/k0s-v1.37.1+k0s.0-arm";
      hash = "sha256-T4F1D+bkqjaCcoKgFCHxV9/ZlKoREUra75sXemgiAI8=";
    };
    aarch64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.37.1+k0s.0/k0s-v1.37.1+k0s.0-arm64";
      hash = "sha256-RXGqyBfKl98K5+DMDikdVpo1o6jPAIkey0hgh6ehcfc=";
    };
    x86_64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.37.1+k0s.0/k0s-v1.37.1+k0s.0-amd64";
      hash = "sha256-9EGBAHzsu1k/j8i8vzD4NjJ38/fTaNG8LvcnSbyzMUg=";
    };
  };
}
