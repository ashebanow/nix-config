#!/usr/bin/env python3
"""Export API keys from a SOPS-encrypted YAML file as shell env vars.

Reads a decrypted YAML stream from stdin and outputs 'export NAME=VALUE'
for every key whose name contains 'api-key' or 'master-key'.
Hyphens in key names are converted to underscores and uppercased.

Usage:
  sops -d secrets/secrets.yaml | sops-export-keys.py
  eval $(sops -d secrets/secrets.yaml | sops-export-keys.py)
"""

import sys
import re

try:
    import yaml
except ImportError:
    print("error: PyYAML is required. Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

data = yaml.safe_load(sys.stdin)

for key, value in data.items():
    if "api-key" in key or "master-key" in key:
        name = re.sub(r"[^a-zA-Z0-9]", "_", key).upper()
        print(f"export {name}={value!r}")
