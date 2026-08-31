import pytest

import update


def fetch(*names):
    return [{"name": name, "url": "", "unpack": True, "hash": ""} for name in names]


def test_names_used_once_are_accepted():
    update.refuse_duplicate_names(fetch("k0s", "runc", "runc/extra"))


def test_a_name_used_twice_stops_the_run():
    with pytest.raises(SystemExit):
        update.refuse_duplicate_names(fetch("k0s", "runc/extra", "runc/extra"))
