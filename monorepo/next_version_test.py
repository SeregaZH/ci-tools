"""What the next release of a part is, and what it must never be.

The version is the only thing a publish invents, so the arithmetic is worth
pinning down: separate version lines per part, the bump levels, and the rule
that nothing but a tag names a version.

The pure functions are called directly; one test drives the script against a
real temporary repository, because the part that actually breaks is the git
plumbing, not the addition.
"""

import os
import subprocess
import sys
from pathlib import Path

import pytest
from next_version import bump_from, next_version, parse

TAGS = ["api/v0.1.0", "api/v0.2.0", "api/v0.10.0", "workflows/v1.4.2"]

#: Passed explicitly everywhere: when ci-tools is a submodule the module-level
#: default comes from the consumer's .ci-tools.env, and these assertions must
#: not depend on which repository happens to be checked out around them.
SLASH_V = "/v"

SCRIPT = Path(__file__).with_name("next_version.py")


# -- one version line per part --------------------------------------------
def test_a_part_only_ever_sees_its_own_tags():
    """Releasing the API must not be able to read the workflows' version."""
    assert parse(TAGS, "api", SLASH_V) == [(0, 1, 0), (0, 2, 0), (0, 10, 0)]
    assert parse(TAGS, "workflows", SLASH_V) == [(1, 4, 2)]


def test_the_newest_is_the_highest_not_the_last_string():
    """0.10.0 is newer than 0.9.0 — a lexical sort says otherwise."""
    assert next_version(["api/v0.9.0", "api/v0.10.0"], "api", "patch", SLASH_V) == (0, 10, 1)


def test_a_part_that_has_never_shipped_starts_at_0_1_0():
    assert next_version(TAGS, "agent-tools", "patch", SLASH_V) == (0, 1, 0)
    assert next_version([], "api", "major", SLASH_V) == (0, 1, 0)


@pytest.mark.parametrize(
    "tag",
    ["api/v1.2", "api/1.2.3", "api/vX.Y.Z", "api-1.2.3", "v1.2.3", "api/v1.2.3-rc1"],
)
def test_a_tag_that_is_not_a_release_cannot_decide_the_next_one(tag):
    """Only `<part><sep>X.Y.Z` names a version, so only it is counted."""
    assert parse([tag], "api", SLASH_V) == []


# -- the separator is the only thing repos disagree on (CI_TAG_SEP) -------
CHART_TAGS = ["monitoring-extensions-0.1.0", "monitoring-extensions-0.9.0", "other-2.0.0"]


def test_a_repo_can_use_a_dash_instead_of_a_slash():
    assert parse(CHART_TAGS, "monitoring-extensions", "-") == [(0, 1, 0), (0, 9, 0)]
    assert next_version(CHART_TAGS, "monitoring-extensions", "minor", "-") == (0, 10, 0)


def test_one_part_is_not_a_prefix_of_another():
    """`monitoring` must not harvest `monitoring-extensions-0.1.0`."""
    assert parse(CHART_TAGS, "monitoring", "-") == []


# -- how far to bump ------------------------------------------------------
@pytest.mark.parametrize(
    "bump,expected",
    [("major", (1, 0, 0)), ("minor", (0, 11, 0)), ("patch", (0, 10, 1))],
)
def test_each_bump_level_zeroes_what_it_should(bump, expected):
    assert next_version(TAGS, "api", bump, SLASH_V) == expected


@pytest.mark.parametrize(
    "message,expected",
    [
        ("Add a route", "patch"),
        ("Rename the claim endpoint #major", "major"),
        ("Add lease metrics\n\n#minor", "minor"),
        ("", "patch"),
    ],
)
def test_the_commit_message_chooses_the_bump(message, expected):
    assert bump_from(message) == expected


def test_an_unknown_bump_level_is_refused_rather_than_guessed():
    with pytest.raises(ValueError):
        next_version(TAGS, "api", "pathc", SLASH_V)


# -- against a real repository --------------------------------------------
def run(cwd, *args, expect=0, sep="/v"):
    """The script in a temporary repo, with the tag scheme pinned explicitly."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT), *args], cwd=cwd, capture_output=True, text=True,
        env={**os.environ, "CI_TAG_SEP": sep},
    )
    assert result.returncode == expect, result.stderr
    return result


@pytest.fixture
def repo(tmp_path):
    """A repository with one commit, and no tags yet."""
    for args in (
        ("init", "-q", "-b", "main"),
        ("config", "user.email", "t@example.invalid"),
        ("config", "user.name", "t"),
        ("commit", "-q", "--allow-empty", "-m", "first"),
    ):
        subprocess.run(("git", *args), cwd=tmp_path, check=True, capture_output=True)
    return tmp_path


def test_the_script_reads_tags_and_the_commit_message(repo):
    subprocess.run(("git", "tag", "api/v0.3.4"), cwd=repo, check=True)

    assert "version=0.3.5" in run(repo, "api").stdout

    subprocess.run(
        ("git", "commit", "-q", "--allow-empty", "-m", "Break the contract #major"),
        cwd=repo, check=True, capture_output=True,
    )
    out = run(repo, "api").stdout

    assert "version=1.0.0" in out
    assert "tag=api/v1.0.0" in out


def test_ci_tag_sep_changes_the_tag_the_script_writes(repo):
    """The chart repos tag `<chart>-X.Y.Z`, and read the same tags back."""
    subprocess.run(("git", "tag", "monitoring-extensions-0.1.0"), cwd=repo, check=True)
    out = run(repo, "monitoring-extensions", sep="-").stdout

    assert "version=0.1.1" in out
    assert "tag=monitoring-extensions-0.1.1" in out


def test_an_existing_tag_is_refused_rather_than_republished(repo, monkeypatch):
    """A checkout with no tags would restart at 0.1.0 and overwrite it.

    That is the shape this guard exists for — not bad arithmetic, but a tag
    list that is missing the releases it should have contained.
    """
    import next_version

    def blind(*args):
        """`git tag -l` with no filter sees nothing; the one tag is there."""
        if args == ("tag", "-l"):
            return ""
        if args[:2] == ("tag", "-l"):
            return "api/v0.1.0\n" if args[2] == "api/v0.1.0" else ""
        return "a commit"

    monkeypatch.setattr(next_version, "_git", blind)

    assert next_version.main(["api"]) == 1
