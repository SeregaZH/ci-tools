#!/usr/bin/env python3
"""The next version for one part of a monorepo, read from that part's own tags.

Nothing in a repository names its own version: `<part><sep>X.Y.Z` tags are
separate version lines, and this reads the highest tag on one line and bumps
it. That is what lets a merge touching one part release it and move nothing
else.

    ci-tools/monorepo/next_version.py <part> [major|minor|patch]

The bump level defaults to reading the HEAD commit message for `#major` or
`#minor`. Prints `version=` and `tag=`, and appends them to $GITHUB_OUTPUT when
the pipeline sets it — so the same command that runs in `publish` also answers
"what would the next release be?" on a laptop.

The separator between the part and the version is the one thing repositories
disagree on, so it is the one thing configurable, via CI_TAG_SEP in the
consumer's .ci-tools.env:

    api/v1.2.3              CI_TAG_SEP="/v"   (the default)
    monitoring-extensions-1.2.3   CI_TAG_SEP="-"
"""

from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys


def load_env() -> None:
    """The consumer's .ci-tools.env — the same file lib.sh sources.

    Read here as well so this answers correctly when run straight from a
    laptop, not only when a bash script in this directory sourced lib.sh first.
    A value already in the environment wins, so CI_TAG_SEP=x still overrides
    the file.
    """
    path = pathlib.Path(__file__).resolve().parents[2] / ".ci-tools.env"
    if not path.is_file():
        return
    for line in path.read_text().splitlines():
        key, sep, value = line.strip().partition("=")
        if sep and not key.startswith("#"):
            os.environ.setdefault(key.strip(), value.strip().strip("\"'"))


load_env()

#: What sits between the part name and the digits. See the module docstring.
SEP = os.environ.get("CI_TAG_SEP", "/v")

#: The first release of a part that has never been published.
FIRST = (0, 1, 0)


def pattern(part: str, sep: str = SEP) -> re.Pattern[str]:
    """Exactly this part's release tags — anything else must not be counted.

    The prefix is escaped rather than interpolated so a part name containing a
    regex character cannot widen the match, and the anchors are what stop
    `api/v1.2.3-rc1` or `api-extras/v1.0.0` from deciding the API's version.
    """
    return re.compile(re.escape(part + sep) + r"(\d+)\.(\d+)\.(\d+)$")


def parse(tags: list[str], part: str, sep: str = SEP) -> list[tuple[int, int, int]]:
    """The versions on this part's tag line, ignoring everything else.

    Sorting is done on the parsed triple rather than on the string, so 0.10.0
    is newer than 0.9.0 — the one comparison a lexical sort gets wrong, and it
    only shows up once a part has shipped ten times.
    """
    matcher = pattern(part, sep)
    found = []
    for tag in tags:
        if match := matcher.fullmatch(tag.strip()):
            found.append(tuple(int(n) for n in match.groups()))
    return sorted(found)


def bump_from(message: str) -> str:
    """`#major` and `#minor` in the merge commit, patch when it says nothing."""
    if "#major" in message:
        return "major"
    if "#minor" in message:
        return "minor"
    return "patch"


def next_version(
    tags: list[str], part: str, bump: str, sep: str = SEP
) -> tuple[int, int, int]:
    """The highest version on this part's line, bumped — or the first one."""
    if bump not in ("major", "minor", "patch"):
        raise ValueError(f"unknown bump level {bump!r}")

    versions = parse(tags, part, sep)
    if not versions:
        return FIRST

    major, minor, patch = versions[-1]
    if bump == "major":
        return major + 1, 0, 0
    if bump == "minor":
        return major, minor + 1, 0
    return major, minor, patch + 1


def _git(*args: str) -> str:
    return subprocess.run(
        ("git", *args), capture_output=True, text=True, check=True
    ).stdout


def main(argv: list[str]) -> int:
    if not argv or len(argv) > 2:
        print(__doc__, file=sys.stderr)
        return 2
    part, bump = argv[0], (argv[1] if len(argv) > 1 else "")

    bump = bump or bump_from(_git("log", "-1", "--pretty=%B"))
    version = ".".join(
        str(n) for n in next_version(_git("tag", "-l").splitlines(), part, bump)
    )
    tag = f"{part}{SEP}{version}"

    # Reachable when the tag list is incomplete rather than when the maths is
    # wrong: a checkout without `fetch-depth: 0` sees no tags, restarts at
    # 0.1.0 and would quietly replace the first release under every pin naming
    # it. Asking git directly for the one tag catches that.
    if _git("tag", "-l", tag).strip():
        print(f"tag {tag} already exists — refusing to republish", file=sys.stderr)
        return 1

    for name, value in (("version", version), ("tag", tag)):
        print(f"{name}={value}")
        if output := os.environ.get("GITHUB_OUTPUT"):
            with open(output, "a") as handle:
                handle.write(f"{name}={value}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
