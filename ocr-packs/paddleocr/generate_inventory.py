#!/usr/bin/env python3
"""Print a compact installed-package inventory for the release artifact."""

from importlib import metadata
import json


packages = []
for distribution in metadata.distributions():
    record = {
        "name": distribution.metadata.get("Name", distribution.name),
        "version": distribution.version,
        "license": distribution.metadata.get("License", "UNKNOWN"),
        "homePage": distribution.metadata.get("Home-page", ""),
    }
    packages.append(record)

print(json.dumps(sorted(packages, key=lambda item: item["name"].lower()), indent=2, ensure_ascii=False))
