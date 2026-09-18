{
  lib,
  pkgs,
  nixpkgs,
  k0sNix,
}:
let
  marker = "<!-- readme-example -->";
  parts = lib.splitString "${marker}\n```nix\n" (builtins.readFile ../README.md);
  snippet = lib.optionalString (lib.length parts > 1) (
    lib.elemAt (lib.splitString "\n```\n" (lib.elemAt parts 1)) 0
  );

  # A committed file, not builtins.toFile: nix flake check --no-build
  # evaluates read-only, where a toFile path is computed and never written.
  exampleFile = ./readme-example/example.nix;

  matches = lib.assertMsg (
    builtins.readFile exampleFile == snippet + "\n"
  ) "the ${marker} block in README.md and checks/readme-example/example.nix differ";

  example = import exampleFile;

  node =
    (example.outputs {
      inherit nixpkgs;
      k0s-nix = k0sNix;
    }).nixosConfigurations.my-node;

  # Without the context discard this check builds a whole NixOS closure.
  toplevel = builtins.unsafeDiscardStringContext node.config.system.build.toplevel.drvPath;
in
assert matches;
pkgs.runCommand "k0s-readme-example"
  {
    preferLocalBuild = true;
    allowSubstitutes = false;
    inherit toplevel;
    k0sPackage = node.config.services.k0s.package.name;
  }
  ''
    echo "system: $toplevel"
    echo "services.k0s.package: $k0sPackage"
    touch $out
  ''
