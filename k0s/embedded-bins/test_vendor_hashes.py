"""
Cover the parts of vendor_hashes.py that need no build.

Resolving a hash needs the network and a Go toolchain, so what is left
to a test is the reading and writing of a table and the reading of a
build log. Both are where a silent mistake would be written into a file
nobody re-reads.
"""

import pytest

import vendor_hashes


TABLE = """{
  # A comment the rewrite has to leave alone.
  vendorHashes = {
    "0.13.19" = "sha256-first=";
    "0.16.3" = "sha256-third=";
  };

  inherit (component) version;
}
"""


@pytest.fixture
def table(tmp_path):
    """A kine.nix holding two hashes, a comment and an unrelated attribute."""
    path = tmp_path / "kine.nix"
    path.write_text(TABLE)
    return path


def test_reads_every_entry(table):
    assert vendor_hashes.read(table) == {
        "0.13.19": "sha256-first=",
        "0.16.3": "sha256-third=",
    }


def test_writing_what_was_read_changes_nothing(table):
    vendor_hashes.write(table, vendor_hashes.read(table))

    assert table.read_text() == TABLE


def test_a_new_entry_lands_in_version_order(table):
    entries = vendor_hashes.read(table) | {"0.14.16": "sha256-second="}

    vendor_hashes.write(table, entries)

    assert list(vendor_hashes.read(table)) == ["0.13.19", "0.14.16", "0.16.3"]


def test_an_entry_left_out_is_dropped(table):
    vendor_hashes.write(table, {"0.16.3": "sha256-third="})

    assert list(vendor_hashes.read(table)) == ["0.16.3"]


def test_the_surrounding_file_survives(table):
    vendor_hashes.write(table, {"9.9.9": "sha256-only="})

    text = table.read_text()
    assert "# A comment the rewrite has to leave alone." in text
    assert "inherit (component) version;" in text


def test_a_file_without_a_table_stops_the_run(table):
    table.write_text("{ }\n")

    with pytest.raises(SystemExit):
        vendor_hashes.read(table)


def mismatch_log(name, got):
    return (
        f"building '/nix/store/{'a' * 32}-{name}.drv'...\n"
        f"error: hash mismatch in fixed-output derivation "
        f"'/nix/store/{'b' * 32}-{name}.drv':\n"
        f"         specified: {vendor_hashes.PLACEHOLDER}\n"
        f"            got:    {got}\n"
    )


def test_reads_the_hash_a_derivation_wanted():
    log = mismatch_log("kine-0.16.3-go-modules", "sha256-real=")

    assert vendor_hashes.mismatches(log) == {"kine-0.16.3": "sha256-real="}


def test_reads_a_k0s_version_carrying_its_own_suffix():
    log = mismatch_log("k0s-1.36.3+k0s.2-go-modules", "sha256-real=")

    assert vendor_hashes.mismatches(log) == {"k0s-1.36.3+k0s.2": "sha256-real="}


def test_reads_every_derivation_the_build_reported():
    log = mismatch_log("k0s-1.36.3+k0s.2-go-modules", "sha256-one=") + mismatch_log(
        "kine-0.16.3-go-modules", "sha256-two="
    )

    assert len(vendor_hashes.mismatches(log)) == 2


def test_a_mismatch_we_do_not_own_stops_the_run():
    log = mismatch_log("etcdserver-3.6.14-go-modules", "sha256-real=")

    with pytest.raises(SystemExit):
        vendor_hashes.mismatches(log)


def test_a_build_that_reported_nothing_reads_as_nothing():
    assert vendor_hashes.mismatches("") == {}
