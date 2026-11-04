#!/usr/bin/env python3
import copy, importlib.util, json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('report',root/'scripts/check-report.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
catalog=json.loads((root/'content/controls.json').read_text())
base=dict(baseline_version=catalog['version'],target='synthetic-validator-test',evidence_scope='synthetic unit test',assessed_at='2026-11-03T00:00:00Z',checks=[dict(id=x['id'],status='MANUAL',rationale='Evidence not collected',evidence=[],exception=None) for x in catalog['controls']])
assert m.validate(catalog,base)['coverage_percent']==0
for name,mutate in [
 ('missing ID',lambda d:d['checks'].pop()),
 ('duplicate ID',lambda d:d['checks'].__setitem__(1,copy.deepcopy(d['checks'][0]))),
 ('unsupported PASS',lambda d:d['checks'][0].update(status='PASS')),
 ('unjustified N/A',lambda d:d['checks'][0].update(status='N/A'))]:
    d=copy.deepcopy(base);mutate(d)
    try:m.validate(catalog,d)
    except ValueError:print('PASS | validator rejects '+name)
    else:raise AssertionError(name)
d=copy.deepcopy(base)
for c in d['checks']:c.update(status='N/A',na_reason='Synthetic denominator test only',na_approver='test')
assert m.validate(catalog,d)['coverage_percent'] is None
print('PASS | empty applicable denominator is undefined, never 100%')
d=copy.deepcopy(base);d['checks'][0].update(status='PASS',rationale='Synthetic supported observation',evidence=[dict(source='fixture',observed_at=base['assessed_at'],observation='expected value',method='unit test')])
assert m.validate(catalog,d)['coverage_percent']==3.6
print('PASS | one evidenced result retains fixed 28-control denominator')
