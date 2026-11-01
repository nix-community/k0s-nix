{
  version = "1.34.12+k0s.0";
  srcs = {
    armv7l-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.34.12+k0s.0/k0s-v1.34.12+k0s.0-arm";
      hash = "sha256-DQLIhhk4qIyTZU6NA0aVvIEON/5mTBvs5H8JtbfmSjY=";
    };
    aarch64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.34.12+k0s.0/k0s-v1.34.12+k0s.0-arm64";
      hash = "sha256-deDvnZSsNl31pGMU5cm+jkA48iv/75B2kz0FYeBsmzQ=";
    };
    x86_64-linux = {
      url = "https://github.com/k0sproject/k0s/releases/download/v1.34.12+k0s.0/k0s-v1.34.12+k0s.0-amd64";
      hash = "sha256-hTas+Sn8fNb2h8mmPYRgZSX95vwhahoIG0oBbgs9wh4=";
    };
  };
}
