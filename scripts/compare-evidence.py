#!/usr/bin/env python3
"""Compare deterministic counts and the portable coverage acceptance gate."""
import hashlib
import json
from pathlib import Path

expected = json.loads(Path('docs/iterations/01a/evidence.json').read_text())
actual_sim = json.loads(Path('work/uc-sim-report.json').read_text())
actual_property = json.loads(Path('work/property-report.json').read_text())
actual_coverage = json.loads(Path('work/coverage.json').read_text())
rows = []
for key in ['scenarios', 'passed', 'failed']:
    rows.append(('sim.' + key, expected['uc_sim'][key], actual_sim[key]))
for key in ['seed', 'streams', 'engines', 'executions', 'events_per_engine', 'plans', 'correction_plans', 'failures']:
    rows.append(('property.' + key, expected['property'][key], actual_property[key]))
# Different Swift/LLVM versions count executable lines differently; compare the agreed gate.
rows.append(('coverage >= 85%', True, actual_coverage['percent'] >= 85))
for row in expected['dataset_hashes']:
    rows.append(('sha256:' + row['path'], row['sha256'], hashlib.sha256(Path(row['path']).read_bytes()).hexdigest()))
print('| Metric | Report | Current | Match |')
print('|---|---|---|---|')
for key, before, after in rows:
    print(f'| {key} | {before} | {after} | {"совпало" if before == after else "РАСХОЖДЕНИЕ"} |')
raise SystemExit(0 if all(a == b for _, a, b in rows) else 1)
