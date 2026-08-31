import pytest

import extract


BELOW_1_36 = (
    "CGO_ENABLED=1 CGO_CFLAGS='' GOOS=linux go build -tags=osusergo "
    "-buildvcs=false -trimpath -ldflags='-w -s "
    "-X github.com/k0sproject/k0s/pkg/build.Version=v1.33.13-dev+k0s "
    "-X \"github.com/k0sproject/k0s/pkg/build.EulaNotice=\" "
    "-extldflags=-static' -o 'k0s' main.go"
)

FROM_1_36 = (
    "CGO_ENABLED=0 CGO_CFLAGS='' GOOS=linux go build -tags=osusergo "
    "-buildvcs=false -trimpath -ldflags='-w -s' -o 'k0s.bare' main.go"
)


def test_the_build_line_is_found_among_the_recipe():
    output = f"rm -f -- 'k0s'\n{BELOW_1_36}\ncat -- bindata_linux >>k0s\n"

    assert extract.build_command(output) == BELOW_1_36


def test_a_line_continued_by_a_backslash_is_joined_first():
    output = "CGO_ENABLED=0 go build \\\n  -trimpath -o 'k0s' main.go\n"

    assert extract.build_command(output).endswith("-trimpath -o 'k0s' main.go")


@pytest.mark.parametrize(
    "output",
    [
        pytest.param("touch .bins.linux.stamp\n", id="none"),
        pytest.param(f"{BELOW_1_36}\n{FROM_1_36}\n", id="two"),
    ],
)
def test_anything_but_one_build_line_stops_the_run(output):
    with pytest.raises(SystemExit):
        extract.build_command(output)


def test_the_leading_assignments_are_the_environment():
    parameters = extract.build_parameters(BELOW_1_36)

    assert parameters["env"] == {
        "CGO_ENABLED": "1",
        "CGO_CFLAGS": "",
        "GOOS": "linux",
    }


@pytest.mark.parametrize(
    ("command", "expected"),
    [(BELOW_1_36, "1"), (FROM_1_36, "0")],
    ids=["below-1.36", "from-1.36"],
)
def test_cgo_is_read_per_minor(command, expected):
    assert extract.build_parameters(command)["env"]["CGO_ENABLED"] == expected


@pytest.mark.parametrize(
    "command", [BELOW_1_36, FROM_1_36], ids=["below-1.36", "from-1.36"]
)
def test_the_go_flags_are_neither_the_linker_flags_nor_the_output(command):
    parameters = extract.build_parameters(command)

    assert parameters["go_flags"] == ["-tags=osusergo", "-buildvcs=false", "-trimpath"]


def test_each_stamp_is_one_entry():
    parameters = extract.build_parameters(BELOW_1_36)

    assert parameters["ldflags"] == [
        "-w",
        "-s",
        "-X github.com/k0sproject/k0s/pkg/build.Version=v1.33.13-dev+k0s",
        "-X github.com/k0sproject/k0s/pkg/build.EulaNotice=",
        "-extldflags=-static",
    ]


def test_a_command_without_linker_flags_stops_the_run():
    with pytest.raises(SystemExit):
        extract.build_parameters("CGO_ENABLED=0 go build -trimpath -o 'k0s' main.go")
