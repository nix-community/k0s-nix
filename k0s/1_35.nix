{
  version = "1.35.8+k0s.0";
  srcs = {
    armv7l-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.35.8+k0s.0/k0s-v1.35.8+k0s.0-arm";
      hash = "sha256-8tRWSEFnXUG3OypsSlLMNNTqYPZsTKpMJs1Ks4zz/+8=";
    };
    aarch64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.35.8+k0s.0/k0s-v1.35.8+k0s.0-arm64";
      hash = "sha256-1rEztCHmBRwhMdesrCMgPGhgg+KmhkoXxa3iVifrICo=";
    };
    x86_64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.35.8+k0s.0/k0s-v1.35.8+k0s.0-amd64";
      hash = "sha256-nsfsOcTLfxovWVpBNJnMvW5xPpHc79dwnhnJpFV/k4w=";
    };
  };
}
