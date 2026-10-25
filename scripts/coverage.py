#!/usr/bin/env python3
"""Extract UCCore executable-line coverage from SwiftPM's llvm-cov export."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--minimum', type=float, default=85)
parser.add_argument('--output', default='work/coverage.json')
args = parser.parse_args()
candidates = list(Path('.build').glob('*/debug/codecov/*.json'))
candidates += list(Path('.build/out/Products/Debug/codecov').glob('*.json'))
if not candidates:
    raise SystemExit('No SwiftPM coverage export. Run swift test --enable-code-coverage first.')
report = json.loads(max(candidates, key=lambda p: p.stat().st_mtime).read_text())
rows = []
for data in report['data']:
    for file in data['files']:
        if '/Sources/UCCore/' in file['filename']:
            lines = file['summary']['lines']
            rows.append(dict(file='Sources/UCCore/' + file['filename'].split('/Sources/UCCore/')[1],
                             covered=lines['covered'], count=lines['count']))
assert rows, 'UCCore missing from coverage export'
covered = sum(r['covered'] for r in rows)
count = sum(r['count'] for r in rows)
result = dict(covered=covered, count=count, percent=100 * covered / count, files=rows)
Path(args.output).parent.mkdir(parents=True, exist_ok=True)
Path(args.output).write_text(json.dumps(result, indent=2) + '\n')
print(f'UCCore coverage: {covered}/{count} = {result["percent"]:.2f}% (required {args.minimum}%)')
raise SystemExit(0 if result['percent'] >= args.minimum else 1)
