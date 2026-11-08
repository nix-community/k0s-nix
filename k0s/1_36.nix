{
  version = "1.36.6+k0s.0";
  srcs = {
    armv7l-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.36.6+k0s.0/k0s-v1.36.6+k0s.0-arm";
      hash = "sha256-mZ3qHMEhMazg0C95fc36WPxyH2k+nNiWmBykiyagOvM=";
    };
    aarch64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.36.6+k0s.0/k0s-v1.36.6+k0s.0-arm64";
      hash = "sha256-z0djxsDgi5xTs8Ps1/Nfe+5Qr/KiNH+lqMxMR6tImy8=";
    };
    x86_64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.36.6+k0s.0/k0s-v1.36.6+k0s.0-amd64";
      hash = "sha256-YLrDnU7YKSrbhXalWGY4nN5HAPm+fRUlh+FfiqZ8Evw=";
    };
  };
}
