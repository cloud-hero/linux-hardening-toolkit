#!/usr/bin/env python3
"""Validate the distributed toolkit without connecting to or modifying a server."""
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
for name in ('assess.sh', 'collect-report.sh', 'baseline.py', 'check-report.py', 'vulnerability-context.py'):
    assert (root/name).read_bytes() == (root/'scripts'/name).read_bytes(), name
for name in ('controls.json', 'baseline-paths.json'):
    assert (root/name).read_bytes() == (root/'content'/name).read_bytes(), name
assert (root/'linux-server-hardening-guide.md').read_text() == (root/'content/guide.md').read_text().replace('](../', '](')
for name in ('test-baseline.py', 'test-report.py', 'test-guide-fixes.py', 'test-vulnerability-context.py'):
    subprocess.run([sys.executable, str(root/'scripts'/name)], check=True)
catalog = json.loads((root/'controls.json').read_text())
ids = [c['id'] for c in catalog['controls']]
assert len(ids) == len(set(ids)) == 28
assert re.findall(r'^([A-Z]+-\d{2}) \| ', (root/'linux-assessment-prompt.txt').read_text(), re.M) == ids
with (root/'controls.csv').open() as source:
    assert [row['id'] for row in csv.DictReader(source)] == ids
for name in ('report-template.json', 'lab-assessment-report.json'):
    report = json.loads((root/name).read_text())
    assert report['baseline_version'] == catalog['version']
    assert [c['id'] for c in report['checks']] == ids
report = json.loads((root/'lab-assessment-report.json').read_text())
for check in report['checks']:
    for evidence in check['evidence']:
        path = (root/evidence['source']).resolve()
        assert path.is_relative_to(root) and path.is_file(), evidence['source']
subprocess.run([sys.executable, str(root/'check-report.py'), '--catalog', str(root/'controls.json'), str(root/'lab-assessment-report.json')], check=True)
for line in (root/'SHA256SUMS').read_text().splitlines():
    expected, name = line.split('  ', 1)
    path = (root/name).resolve()
    assert path.is_relative_to(root) and path.is_file(), name
    assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, 'Checksum mismatch: '+name
print('PASS | Distributed tools, fixture suites, fixed catalogue, report evidence and publication checksums.')
