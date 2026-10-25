#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json
from pathlib import Path
manifest=json.loads(Path('Resources/manifest.json').read_text())
assert manifest['resources']==[], 'Resource downloads are introduced in iteration 01b.'
print('resources=0 iteration=01a download=not_required')
PY
