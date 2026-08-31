{ lib, pkgs }:
let
  pins = import ../k0s/embedded-bins/pins.nix { inherit lib; };
  components = pkgs.callPackage ../k0s/embedded-bins/components { };
  sourceBuilds = pkgs.callPackage ../k0s/source.nix { };

  # Which mechanism a minor uses is read from the pins rather than taken from
  # source.nix, so the check decides how to read the payload without asking the
  # package what it built. Sharing one helper would make the two agree by
  # construction, and a wrong boundary would then pass.
  mechanismFor =
    minor: if lib.versionAtLeast (pins.read minor).k0sVersion "1.36" then "zip" else "bindata";

  manifest = lib.mapAttrsToList (minor: k0s: {
    inherit minor k0s;
    inherit (k0s) payload offsets;
    components = lib.attrValues components.${minor};
    k0sVersion = (pins.read minor).k0sVersion;
    payloadBinaries = (pins.read minor).upstream.payloadBinaries;
    mechanism = mechanismFor minor;
  }) sourceBuilds.withPayload;

  # zipfile locates the archive by its central directory, the way
  # pkg/assets/stage.go's zip.OpenReader does, so a k0s binary with a zip behind
  # it reads here exactly as it does at runtime.
  readZipPayload = pkgs.writeText "read-k0s-zip-payload.py" ''
    import os
    import sys
    import zipfile

    binary, staging = sys.argv[1:]
    expected = sorted(os.listdir(staging))

    with zipfile.ZipFile(binary) as payload:
        names = sorted(payload.namelist())
        if names != expected:
            sys.exit(f"the payload holds {names}, expected {expected}")
        for name in names:
            with open(os.path.join(staging, name), "rb") as component:
                if payload.read(name) != component.read():
                    sys.exit(f"the staged {name} is not the component built")

    print(f"payload: {', '.join(names)}")
  '';

  # Below 1.36 the blob is a run of gzip members with no framing of its own, and
  # the table that locates them is the generated Go source the build compiled
  # in. Reading the entries out of it is what pkg/assets/stage.go does at
  # runtime, and decompressing the blob as a whole would pass without ever
  # proving an entry starts where the table says.
  readBindataPayload = pkgs.writeText "read-k0s-bindata-payload.py" ''
    import gzip
    import os
    import re
    import sys

    blob, offsets, staging = sys.argv[1:]
    expected = sorted(f"bin/{name}.gz" for name in os.listdir(staging))

    entry = re.compile(r'"([^"]+)":\s*\{\s*(\d+),\s*(\d+),\s*(\d+)\s*\}')
    with open(offsets) as table:
        entries = {
            name: (int(offset), int(size), int(original))
            for name, offset, size, original in entry.findall(table.read())
        }

    if sorted(entries) != expected:
        sys.exit(f"the table holds {sorted(entries)}, expected {expected}")

    with open(blob, "rb") as payload:
        data = payload.read()

    for name, (offset, size, original) in sorted(entries.items()):
        staged = gzip.decompress(data[offset : offset + size])
        if len(staged) != original:
            sys.exit(f"{name} unpacks to {len(staged)} bytes, the table says {original}")
        binary = os.path.basename(name).removesuffix(".gz")
        with open(os.path.join(staging, binary), "rb") as component:
            if staged != component.read():
                sys.exit(f"the staged {name} is not the component built")

    print(f"payload: {', '.join(sorted(entries))}, {len(data)} bytes")
  '';
in
pkgs.runCommand "k0s-embedded-bins-payload"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.python3
    ];
    passAsFile = [ "manifest" ];
    manifest = builtins.toJSON manifest;

    # The payload is compressed inside the binary, so nothing in the output
    # spells a component's store path where the reference scanner would find
    # it. Only the store's own graph settles whether the closure holds them.
    exportReferencesGraph = lib.concatMap (entry: [
      "closure-${entry.minor}"
      entry.k0s
    ]) manifest;
  }
  ''
    set -o pipefail
    failed=

    while read -r entry; do
      eval "$(jq -r '@sh "minor=\(.minor) k0s=\(.k0s) k0sVersion=\(.k0sVersion) payload=\(.payload) offsets=\(.offsets) mechanism=\(.mechanism)"' <<<"$entry")"
      eval "components=($(jq -r '@sh "\(.components)"' <<<"$entry"))"

      for component in "''${components[@]}"; do
        if ! grep -qxF "$component" "closure-$minor"; then
          echo "$minor: $component is outside the k0s closure, so a collection takes it" >&2
          failed=1
        fi
      done

      staging=$(mktemp -d)
      for component in "''${components[@]}"; do
        install -m644 -t "$staging" "$component"/bin/*
      done

      # payloadBinaries is upstream's own list of what k0s stages, so a name the
      # payload carries and it does not is a binary nothing will ever ask for.
      for staged in "$staging"/*; do
        binary=$(basename "$staged")
        if ! jq -e --arg name "$binary" \
          '.payloadBinaries | index($name)' <<<"$entry" >/dev/null; then
          echo "$minor: $binary is not a binary k0s stages" >&2
          failed=1
        fi
      done

      # The components cover the whole list now, so the assertion goes both
      # ways: a name k0s stages that the payload lacks is one the node would
      # have to find on PATH, which is the combination vendoring exists to
      # avoid.
      while read -r wanted; do
        if [ ! -e "$staging/$wanted" ]; then
          echo "$minor: the payload carries no $wanted" >&2
          failed=1
        fi
      done < <(jq -r '.payloadBinaries[]' <<<"$entry")

      # Appending a zip behind an ELF either works or leaves an executable that
      # no longer runs, so the binary is asked first.
      reported=$("$k0s"/bin/k0s version)
      echo "$minor: $reported"
      if [ "$reported" != "v$k0sVersion" ]; then
        echo "$minor: expected v$k0sVersion" >&2
        failed=1
      fi

      # k0s reads the payload out of the executable it is running, so the file
      # the wrapper execs has to be the one carrying it.
      if ! grep -qF "$k0s/libexec/k0s" "$k0s/bin/k0s"; then
        echo "$minor: the wrapper does not exec the binary carrying the payload" >&2
        failed=1
      fi

      case "$mechanism" in
        zip)
          if ! python3 ${readZipPayload} "$k0s/libexec/k0s" "$staging"; then
            echo "$minor: the payload does not read back as the components built" >&2
            failed=1
          fi
          ;;
        bindata)
          # stage.go seeks EOF - BinDataSize + offset, so the blob has to be the
          # tail of the binary and nothing may follow it.
          if ! tail -c "$(stat -c%s "$payload")" "$k0s/libexec/k0s" | cmp -s - "$payload"; then
            echo "$minor: the blob is not at the end of the binary" >&2
            failed=1
          fi

          # The offset table is the half that lives inside the binary, and a
          # build that kept the noembedbins tag carries an empty one - which
          # would leave staging to fall back to PATH without saying so.
          for staged in "$staging"/*; do
            binary=$(basename "$staged")
            if ! grep -qaF "bin/$binary.gz" "$k0s/libexec/k0s"; then
              echo "$minor: the binary carries no offset table naming $binary" >&2
              failed=1
            fi
          done

          if ! python3 ${readBindataPayload} "$payload" "$offsets" "$staging"; then
            echo "$minor: the blob is not the components that were built" >&2
            failed=1
          fi
          ;;
      esac
    done < <(jq -c '.[]' "$manifestPath")

    [ -z "$failed" ] || exit 1
    touch $out
  ''
