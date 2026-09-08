# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What this repository is

`ci-tools` is the CI logic for the other repositories in this workspace, kept
as **ordinary scripts rather than inline workflow steps**, so the exact checks a
pull request runs also run on a laptop. It builds nothing, ships nothing and has
no release of its own.

It is consumed as a **git submodule at `<consumer>/ci-tools`**. Two repositories
use it:

| Consumer | Uses |
|---|---|
| `k8s-experiments-charts` | the whole `monorepo/` gate — a matrix over charts, then version/package/push |
| `automation-agent` | `next_version.py` (adoption of the rest is pending) |

Workflows in a consumer stay thin: checkout with `submodules: true`, install
helm, call a script.

## Layout

```
monorepo/     scripts for monorepos that publish independently versioned parts
```

One directory per **kind** of pipeline. A pipeline of a different shape gets its
own directory beside `monorepo/`, never a flag inside it. The path matters to
consumers, so do not move or rename what is already there.

### `monorepo/` — chart monorepos

| Script | Does |
|---|---|
| [`lib.sh`](monorepo/lib.sh) | Sourced by every script. `REPO_ROOT`, `.ci-tools.env`, `group`/`info`/`warn`/`die`/`emit`/`require_cmd`/`chart_dir`. |
| [`install-tools.sh`](monorepo/install-tools.sh) | The pinned toolchain: kubeconform, promtool, helm-unittest. Idempotent. |
| [`discover-charts.sh`](monorepo/discover-charts.sh) | Charts as a **JSON array**, for an Actions matrix. |
| [`select-charts.sh`](monorepo/select-charts.sh) | Charts to publish as a **space-separated list**: explicit name, else the changed set. |
| [`detect-changed-charts.sh`](monorepo/detect-changed-charts.sh) | Charts touched between two commits. |
| [`render-chart.sh`](monorepo/render-chart.sh) | Renders every values profile (`values.yaml` + `ci/*-values.yaml`). |
| [`validate-chart.sh`](monorepo/validate-chart.sh) | The gate: lint → render → kubeconform → promtool → unittest → the consumer's `ci/checks/`. |
| [`validate-charts.sh`](monorepo/validate-charts.sh) | `validate-chart.sh` over several charts, sequentially. |
| [`extract-rule-groups.py`](monorepo/extract-rule-groups.py) | Lifts `groups:` out of rendered `PrometheusRule` CRs so promtool can read them. |
| [`next_version.py`](monorepo/next_version.py) | The next SemVer for one part, from that part's own tags. |
| [`publish-charts.sh`](monorepo/publish-charts.sh) | Version → package → push OCI → tag. Honours `DRY_RUN=1`. |

`discover-charts.sh` and `select-charts.sh` emit **different formats on
purpose** — JSON for a matrix, space-separated for a shell loop. Mixing them
silently produces a bogus chart name, which is why publishing has its own entry
point rather than reusing the discovery one.

## The consumer contract

Everything here is a public interface. A rename, a changed argument order or a
changed output name **breaks another repository's pipeline**, and the failure
surfaces there, not here.

What consumers rely on, and what may not change casually:

- **Script paths.** `ci-tools/monorepo/<name>`.
- **Arguments and emitted names.** `emit charts …` / `emit any …` are read as
  step outputs by name in consumer workflow YAML.
- **The two structural assumptions.** Charts live at
  `charts/<name>/Chart.yaml`; a release is a git tag
  `<part><CI_TAG_SEP><major>.<minor>.<patch>` and is the only place a version is
  written down.
- **`.ci-tools.env`.** Every per-repo value is read from the consumer's root, by
  `lib.sh` and — separately — by `next_version.py`. Adding a setting means
  giving it a default here; **never** add a required one without updating both
  consumers in the same change.

When you do change an interface, grep the consumers:

```bash
grep -rn "ci-tools/" ~/repos/k8s-experiments-charts/.github ~/repos/automation-agent/.github
```

## Conventions

- **Bash, `set -euo pipefail`, source `lib.sh` first.** No GitHub Actions
  dependency anywhere: `group`/`endgroup` degrade to plain echoes, `emit` writes
  `$GITHUB_OUTPUT` only when it is set. A script that cannot run on a laptop is
  a bug.
- **`REPO_ROOT` is the consumer, not this repository.** `lib.sh` resolves it two
  levels up (`monorepo/` → `ci-tools/` → the consumer). A new subdirectory at a
  different depth must fix that path.
- **Fail loudly, never silently.** `die` on a missing tool; `warn` when a check
  is skipped, so a gap is visible in the log rather than passing vacuously.
- **Python 3.10+**, type hints, short Google-style docstrings, 100-character
  lines. Comments explain *why*.
- **Do not reference another repository's spec section numbers.** They mean
  nothing here; state the reason in prose instead.
- **Leave the consumer's tree as you found it.** `publish-charts.sh` writes the
  version into `Chart.yaml` to package, then restores it from a copy.

## Key design decisions (don't undo without reason)

- **Scripts are shared; workflow YAML is not.** The consumers' pipelines differ
  too much to share honestly — one fans out a matrix over charts, another builds
  an image and a chart per part. Sharing the scripts removed the duplication
  that was actually costing something. Do not add reusable `workflow_call`
  workflows for a single consumer.
- **`ci/checks/` is the extension point.** A check only one repository needs
  belongs to that repository. `validate-chart.sh` runs every executable in the
  consumer's `ci/checks/` with the chart directory as its argument. That is why
  the Grafana dashboard rules live in `k8s-experiments-charts`, not here — add
  the next repo-specific check the same way, not with a flag in a shared script.
- **`CI_TAG_SEP` is the only thing configurable about a tag.** The two
  consumers disagree on exactly one character: `api/v1.2.3` versus
  `monitoring-extensions-1.2.3`. A full format-string scheme would be more
  machinery than the disagreement justifies.
- **`OCI_REGISTRY` has no default.** A shared repository must not guess a
  registry; a wrong-but-plausible one is discovered by finding somebody else's
  charts in it.
- **Publishing precedes tagging.** A tag with no artifact behind it is worse
  than a published artifact whose tag lands a second later.
- **promtool is not installed in CI.** A ~110 MB download for one binary is not
  worth paying per run, so PromQL is validated on developer machines only.
  `validate-chart.sh` says so loudly. This is a known gap, not an oversight.
- **`next_version.py` refuses an existing tag.** The guard is not for bad
  arithmetic — it is for a checkout without `fetch-depth: 0`, which sees no
  tags, restarts at 0.1.0 and would overwrite the first release under every pin
  naming it.

## Running and checking

```bash
python3 -m pytest monorepo/next_version_test.py     # the only tests here
bash -n monorepo/*.sh                               # syntax
```

`next_version.py` is the only thing in this repository that **invents** a value
rather than checking one, so it is the only thing with tests. Keep it that way:
test the arithmetic and the git plumbing, not the shell wrappers.

The scripts cannot be exercised from this repository — `REPO_ROOT` resolves
outside it and there are no charts here. Test a real change from a consumer:

```bash
cd ~/repos/k8s-experiments-charts
git -C ci-tools checkout <your-sha>
./ci-tools/monorepo/validate-chart.sh monitoring-extensions
DRY_RUN=1 ./ci-tools/monorepo/publish-charts.sh monitoring-extensions
```

`DRY_RUN=1` packages without pushing or tagging, and is the only safe way to
rehearse a publish.

## Releasing

There is no release. Consumers pin a commit SHA through their submodule and bump
it deliberately:

```bash
git submodule update --remote ci-tools && git commit ci-tools -m "Bump ci-tools"
```

**Push here before pushing a consumer** that points at a new commit — the
consumer's gitlink names a SHA that must already exist on the remote, or its CI
fails at checkout.

## Never delete a file you did not create

**Strict. No exceptions, no judgement calls.**

- **Do not delete, move or rename any file or directory that you did not create
  in the current session.** This holds whether or not the file is tracked by
  git, whether or not it looks stale, generated, duplicated, superseded or
  wrong.
- **Untracked is not permission.** A file's absence from git means it is
  *unbacked*, so deleting it is the one action that cannot be undone.
- **No sweeps.** No `rm -rf` of a directory you did not create, and no
  `find … -exec rm` / `-delete` over the repository.
- **If something looks like it should go, say so and stop.** Name the file, say
  why, and let the human decide.
- Replacing a file's contents counts as deleting it. Read a file before
  overwriting it.
