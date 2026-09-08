# ci-tools

Shared CI scripts for the repositories in this workspace.

CI logic lives here as ordinary scripts rather than inline workflow steps, so
the exact checks a pull request runs also run on a laptop. Workflows stay thin:
checkout, install helm, call a script.

## Layout

One directory per kind of pipeline, so a second kind lands beside the first
instead of on top of it:

| Directory | For |
|---|---|
| [`monorepo/`](monorepo/) | Monorepos that publish independently versioned parts — charts and images per part, one tag line each. Used by `k8s-experiments-charts` and `automation-agent`. |

Everything below describes `monorepo/`.

## Using it

Add it as a submodule at `ci-tools/` — the scripts resolve the repository root
as their own parent directory, so the path matters:

```bash
git submodule add https://github.com/SeregaZH/ci-tools.git ci-tools
```

Then in every job that needs it:

```yaml
- uses: actions/checkout@v4
  with:
    submodules: true
```

and locally, once per clone:

```bash
git submodule update --init
```

Bump the pinned version deliberately:

```bash
git submodule update --remote ci-tools && git commit ci-tools -m "Bump ci-tools"
```

Scripts are then at `ci-tools/monorepo/<script>`:

```bash
./ci-tools/monorepo/install-tools.sh
./ci-tools/monorepo/validate-chart.sh my-chart
```

## Per-repo settings

Everything a consumer needs to say about itself goes in one file at its root,
`.ci-tools.env`, sourced by `lib.sh`. A laptop and a runner therefore read the
same values, and no workflow repeats them.

| Variable | Used by | Meaning |
|---|---|---|
| `OCI_REGISTRY` | `publish-charts.sh` | **Required.** `oci://…` URL charts are pushed to. |
| `CI_TAG_SEP` | `next_version.py` | Between part and version. Default `/v` → `api/v1.2.3`; `-` → `my-chart-1.2.3`. |
| `KUBECONFORM_VERSION`, `PROMETHEUS_VERSION` | `monorepo/install-tools.sh` | Pinned toolchain versions. |
| `RENDER_NAMESPACE` | `render-chart.sh` | Namespace charts are rendered against. |

Example:

```bash
OCI_REGISTRY=oci://ghcr.io/seregazh/charts
CI_TAG_SEP=-
```

## Assumptions about the consumer

Two, both structural:

- charts live at `charts/<name>/Chart.yaml`
- anything in `ci/checks/` is a repo-specific check: `validate-chart.sh` runs
  every executable there with the chart directory as its argument
- a release is a git tag `<part><CI_TAG_SEP><major>.<minor>.<patch>`, and it is
  the only place a version is written down

## Scripts

| Script | Does |
|---|---|
| `monorepo/install-tools.sh` | Installs the pinned toolchain (kubeconform, promtool, helm-unittest). Idempotent. |
| `monorepo/discover-charts.sh` | Lists charts as JSON, for a CI matrix. |
| `monorepo/select-charts.sh` | Chooses charts to publish: explicit name, else changed set. Space-separated. |
| `monorepo/detect-changed-charts.sh` | Charts touched between two commits. |
| `monorepo/render-chart.sh` | Renders every values profile (`values.yaml` + `ci/*-values.yaml`). |
| `monorepo/validate-chart.sh` | lint → render → kubeconform → promtool → unittest, then the consumer's own `ci/checks/`. |
| `monorepo/validate-charts.sh` | `monorepo/validate-chart.sh` over several charts. |
| `monorepo/extract-rule-groups.py` | Lifts rule groups out of `PrometheusRule` CRs so promtool can read them. |
| `monorepo/next_version.py` | Next SemVer for one part, from that part's own tags. |
| `monorepo/publish-charts.sh` | Version → package → push OCI → tag. Honours `DRY_RUN=1`. |

`monorepo/next_version.py` is the only thing here that invents a value rather than
checking one, so it is the only thing with tests:

```bash
python3 -m pytest monorepo/next_version_test.py
```

## What is deliberately not here

- **Checks only one repository needs.** A Grafana dashboard convention is not
  common CI, so it lives in that repository's `ci/checks/` and this gate simply
  runs whatever it finds there.
- **Workflow YAML.** The consumers' pipelines differ too much to share — one
  fans out a matrix over charts, another builds an image and a chart per part.
  Sharing the scripts removes the duplication that was actually costing
  something.
- **promtool in CI.** It is a ~110 MB download for one binary, so
  `install-tools.sh` skips it on runners. PromQL is validated on developer
  machines only, and `validate-chart.sh` says so loudly rather than silently
  passing.
