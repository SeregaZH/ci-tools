#!/usr/bin/env python3
"""Extract Prometheus rule groups from rendered PrometheusRule CRs.

promtool validates a rule file (a top-level `groups:` list), not the Kubernetes
CR that wraps one, so a `promtool check rules` step needs
the groups lifted out first.

    extract-rule-groups.py <rendered-dir> <out-dir>

Writes one file per PrometheusRule and prints how many were found.
"""
import pathlib
import sys

import yaml


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    rendered = pathlib.Path(sys.argv[1])
    out = pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)

    count = 0
    for manifest in sorted(rendered.glob("*.yaml")):
        for index, doc in enumerate(yaml.safe_load_all(manifest.read_text())):
            if not doc or doc.get("kind") != "PrometheusRule":
                continue
            groups = doc.get("spec", {}).get("groups")
            if not groups:
                continue
            name = doc["metadata"]["name"]
            target = out / f"{manifest.stem}-{name}-{index}.yaml"
            target.write_text(yaml.safe_dump({"groups": groups}, sort_keys=False))
            count += 1

    print(count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
