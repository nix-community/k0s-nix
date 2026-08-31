{
  lib,
  runCommand,
  zip,
}:
# pkg/assets/stage.go opens the running k0s executable with zip.OpenReader and
# matches an entry against the plain binary name, so the entries are base names
# and there is no directory and no manifest.
name: components:
runCommand "k0s-payload-${name}" { nativeBuildInputs = [ zip ]; } ''
  binaries=()
  for component in ${lib.escapeShellArgs components}; do
    for binary in "$component"/bin/*; do
      binaries+=("$binary")
    done
  done

  # -j drops the store path so the entry is the bare binary name, -X leaves out
  # the uid, gid and timestamps that would otherwise vary.
  zip -j -X -9 payload.zip "''${binaries[@]}"
  mv payload.zip $out
''
