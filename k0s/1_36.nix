{
  version = "1.36.5+k0s.0";
  srcs = {
    armv7l-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.36.5+k0s.0/k0s-v1.36.5+k0s.0-arm";
      hash = "sha256-AwMgQeghFcHpzCCCPD/2SId1Fu48cVX81lSt4bWq4RE=";
    };
    aarch64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.36.5+k0s.0/k0s-v1.36.5+k0s.0-arm64";
      hash = "sha256-iNcwhm5hD+atMuh3v3ntEOr9SP4U5pn/9vUTPBHVmLc=";
    };
    x86_64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.36.5+k0s.0/k0s-v1.36.5+k0s.0-amd64";
      hash = "sha256-N3zbNy83o8I/H2By5PEYOLRbRjtFjyr90MJgcVf74E8=";
    };
  };
}
