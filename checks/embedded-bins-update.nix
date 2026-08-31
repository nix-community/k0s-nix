{ pkgs, ... }:
pkgs.runCommand "k0s-embedded-bins-update-tests"
  {
    preferLocalBuild = true;
    nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pytest ])) ];
  }
  ''
    cd ${../k0s/embedded-bins}
    # Without this pytest warns on every run: the cache would land beside the
    # tests, in a store path.
    pytest --verbose -p no:cacheprovider
    touch $out
  ''
