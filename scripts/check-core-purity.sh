#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import pathlib,re,sys
bad=[]
for p in sorted(pathlib.Path('Sources/UCCore').rglob('*.swift')):
    text=p.read_text()
    # Strip comments; recognize attributed, scoped, and semicolon-separated imports.
    text=re.sub(r'/\*.*?\*/|//[^\n]*','',text,flags=re.S)
    for match in re.finditer(r'\bimport\s+(?:(?:class|struct|enum|protocol|func|var|let|typealias)\s+)?([A-Za-z_][\w]*)',text):
        if match[1] != 'Foundation': bad.append(str(p))
if bad:
    print('core_purity=FAIL files='+','.join(sorted(set(bad))))
    sys.exit(1)
print('core_purity=PASS')
PY
