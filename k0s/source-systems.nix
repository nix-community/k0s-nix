# The systems the source build is proven on. Imported rather than read out of
# source.nix, because flake.nix decides which attribute names exist with it and
# forcing pkgs in name position recurses through splice.nix.
[
  "aarch64-linux"
  "x86_64-linux"
]
