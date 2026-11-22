{
  version = "1.35.10+k0s.1";
  srcs = {
    armv7l-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.35.10+k0s.1/k0s-v1.35.10+k0s.1-arm";
      hash = "sha256-6m1k66QhMoGAkgVDIiYxetdS05F8eVcfKKqkoB9gXsE=";
    };
    aarch64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.35.10+k0s.1/k0s-v1.35.10+k0s.1-arm64";
      hash = "sha256-0Woar8w8BfGU3u3N15GDAsTbX7aB0vbFS8gGTI8Bh7I=";
    };
    x86_64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.35.10+k0s.1/k0s-v1.35.10+k0s.1-amd64";
      hash = "sha256-Wf0PWrZFzVShJNAwhvHylwtgznP9VxNWOn+7eNpYIPY=";
    };
  };
}
