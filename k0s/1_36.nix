{
  version = "1.36.4+k0s.0";
  srcs = {
    armv7l-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.36.4+k0s.0/k0s-v1.36.4+k0s.0-arm";
      hash = "sha256-z3w15sGVLHoVrQyxu4idxixGoYxIA6Ed1ygikJKk7KU=";
    };
    aarch64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.36.4+k0s.0/k0s-v1.36.4+k0s.0-arm64";
      hash = "sha256-YwH2TZj55Pb7wokrxm0Te7StWEBoUwB3LYORYU1HuKo=";
    };
    x86_64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.36.4+k0s.0/k0s-v1.36.4+k0s.0-amd64";
      hash = "sha256-yh6eaBBzNYRugpZ3f84szWVChOYmW0tdMsNOrYcq+Y8=";
    };
  };
}
