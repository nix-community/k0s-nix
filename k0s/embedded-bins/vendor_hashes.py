"""
Keep the vendorHash tables in step with the pins.

A vendorHash cannot be computed, only read back from a build that fails
on it. So an entry that has gone missing is filled with a placeholder,
the package is built, and the hash the failing fixed-output derivation
reports is written back.

Both tables are keyed by the version the hash belongs to - k0s by its
own, kine by kine's - so a moved pin reads as a missing key and an entry
no minor names any more reads as a surplus one. That is the whole of the
staleness rule, and it needs no memory of what the previous run wrote.
"""

import json
import re
import subprocess
import sys
from collections import namedtuple
from pathlib import Path


HERE = Path(__file__).resolve().parent

# nixpkgs' lib.fakeHash. Any syntactically valid hash would do; this one is
# recognisable in a diff if a run dies between the two writes.
PLACEHOLDER = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

# `version` reads what a table's keys name out of a pin file. `pname` is what
# the vendor derivation is called after, which is how a reported mismatch is
# traced back to the entry that asked for it.
Table = namedtuple("Table", "path pname version")

TABLES = [
    Table(HERE.parent / "source.nix", "k0s", lambda pin: pin["k0sVersion"]),
    Table(
        HERE / "components" / "kine.nix",
        "kine",
        lambda pin: pin["upstream"]["components"]["kine"]["version"],
    ),
]

BINDING = re.compile(r"(?<=  vendorHashes = \{\n).*?(?=^  \};$)", re.S | re.M)
ENTRY = re.compile(r'^\s*"([^"]+)" = "([^"]+)";$', re.M)
MISMATCH = re.compile(
    r"hash mismatch in fixed-output derivation '([^']+)':"
    r"\s*specified:\s*\S+"
    r"\s*got:\s*(\S+)"
)


def refresh(pins: dict[str, dict]) -> None:
    owed = {}
    for table in TABLES:
        recorded = read(table.path)
        wanted = {table.version(pin) for pin in pins.values()}
        write(table.path, {v: recorded.get(v, PLACEHOLDER) for v in wanted})
        owed[table.pname] = wanted - set(recorded)

    if any(owed.values()):
        record(owed, reported(minors_owing(pins, owed)))


def load() -> dict[str, dict]:
    return {p.stem: json.loads(p.read_text()) for p in sorted(HERE.glob("1_*.json"))}


def minors_owing(pins: dict[str, dict], owed: dict[str, set[str]]) -> list[str]:
    return sorted(
        minor
        for minor, pin in pins.items()
        if any(table.version(pin) in owed[table.pname] for table in TABLES)
    )


def reported(minors: list[str]) -> dict[str, str]:
    hashes = {}
    for minor in minors:
        print(f"building k0s-source_{minor} to learn its hashes", file=sys.stderr)
        log = build(minor)
        found = mismatches(log)
        # Every minor here owes a hash, so reporting none means the build
        # failed for some other reason.
        if not found:
            sys.exit(log)
        hashes |= found
    return hashes


def record(owed: dict[str, set[str]], hashes: dict[str, str]) -> None:
    for table in TABLES:
        entries = read(table.path)
        for version in owed[table.pname]:
            name = f"{table.pname}-{version}"
            if name not in hashes:
                sys.exit(f"the build reported no hash for {name}")
            entries[version] = hashes[name]
        write(table.path, entries)


def build(minor: str) -> str:
    command = [
        "nix",
        "build",
        "--keep-going",
        "--no-link",
        f"{HERE.parent.parent}#k0s-source_{minor}",
    ]
    return subprocess.run(command, capture_output=True, text=True).stderr


def mismatches(log: str) -> dict[str, str]:
    hashes = {}
    for drv, hash_ in MISMATCH.findall(log):
        name = drv_name(drv)
        # A mismatch outside the two tables means some other pin is wrong,
        # which is worth stopping for rather than passing over on the way.
        if not any(name.startswith(f"{table.pname}-") for table in TABLES):
            sys.exit(f"unexpected hash mismatch in {name}")
        hashes[name] = hash_
    return hashes


# A store path carries a 32 character hash and a dash ahead of the name.
def drv_name(path: str) -> str:
    return Path(path).name[33:].removesuffix(".drv").removesuffix("-go-modules")


def read(path: Path) -> dict[str, str]:
    text = path.read_text()
    start, end = span(text, path)
    return dict(ENTRY.findall(text[start:end]))


def write(path: Path, entries: dict[str, str]) -> None:
    rendered = "".join(
        f'    "{version}" = "{entries[version]}";\n'
        for version in sorted(entries, key=order)
    )
    text = path.read_text()
    start, end = span(text, path)
    path.write_text(text[:start] + rendered + text[end:])


def span(text: str, path: Path) -> tuple[int, int]:
    match = BINDING.search(text)
    if not match:
        sys.exit(f"{path} carries no vendorHashes table")
    return match.span()


def order(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", version))
