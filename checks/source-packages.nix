{
  lib,
  pkgs,
  packages,
}:
let
  pins = import ../k0s/embedded-bins/pins.nix { inherit lib; };
  sourceBuilds = pkgs.callPackage ../k0s/source.nix { };

  system = pkgs.stdenv.hostPlatform.system;
  supported = lib.elem system (import ../k0s/source-systems.nix);

  # Undiscarded, the report's context asks for the derivations it names, and
  # comparing two names would build k0s from source.
  nameOf = drv: builtins.unsafeDiscardStringContext (baseNameOf drv.drvPath);

  # `bare` builds and boots and then stages nothing, which no build reports.
  wanted = minor: nameOf sourceBuilds.withPayload.${minor};

  exposed =
    name:
    let
      package = packages.${name} or null;
    in
    if package == null then "missing" else nameOf package;

  problems = lib.concatMap (
    minor:
    let
      source = "k0s-source_${minor}";
    in
    lib.optional (exposed "k0s_${minor}" == "missing") "${minor}: no k0s_${minor}"
    ++ (
      if supported then
        lib.optional (
          exposed source != wanted minor
        ) "${minor}: ${source} is ${exposed source}, expected ${wanted minor}"
      else
        lib.optional (
          exposed source != "missing"
        ) "${minor}: ${source} is exposed where the source build is unsupported"
    )
  ) pins.minors;

  # `wanted` reaches a derivation whose meta.platforms excludes an unsupported
  # system, and reading the drvPath of one throws rather than returning.
  report =
    if supported then
      lib.concatStringsSep "\n" (
        map (minor: "${minor}: k0s_${minor}, k0s-source_${minor} -> ${wanted minor}") pins.minors
      )
    else
      lib.concatStringsSep "\n" (
        map (minor: "${minor}: k0s_${minor}, no source build on ${system}") pins.minors
      );
in
pkgs.runCommand "k0s-source-packages"
  {
    preferLocalBuild = true;
    passAsFile = [ "report" ];
    inherit report;
    problems = lib.concatStringsSep "\n" problems;
  }
  ''
    cat "$reportPath"
    echo
    if [ -n "$problems" ]; then
      echo "$problems" >&2
      exit 1
    fi
    touch $out
  ''
