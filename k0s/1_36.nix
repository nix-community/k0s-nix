{
  version = "1.36.4+k0s.1";
  srcs = {
    armv7l-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.36.4+k0s.1/k0s-v1.36.4+k0s.1-arm";
      hash = "sha256-Y4Z8JXWo/XRgxZXh7fwUxt3wYV/MrSpSNPzgsHRYKqQ=";
    };
    aarch64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.36.4+k0s.1/k0s-v1.36.4+k0s.1-arm64";
      hash = "sha256-BPaFyMnCkmLaZKzyb9koRS8Z1EmsWHKVkvaG+RWIIxk=";
    };
    x86_64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.36.4+k0s.1/k0s-v1.36.4+k0s.1-amd64";
      hash = "sha256-GMME1TzdcAlemca4WbJptP7wu4RXnX5xhScakTVpSjE=";
    };
  };
}
