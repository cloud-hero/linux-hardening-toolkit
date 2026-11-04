#!/usr/bin/env python3
"""Validate the fixed assessment denominator and evidence structure, not truth."""
import argparse, collections, datetime, json, sys
from pathlib import Path
STATUSES = ('PASS', 'FAIL', 'WARN', 'MANUAL', 'ERROR', 'N/A')

def timestamp(value):
    if not isinstance(value,str): raise ValueError('UTC timestamp is required')
    parsed=datetime.datetime.fromisoformat(value.replace('Z','+00:00'))
    if parsed.utcoffset()!=datetime.timedelta(0): raise ValueError('Timestamps must include UTC timezone')

def validate(catalog, report):
    if report.get('baseline_version')!=catalog['version']: raise ValueError('Wrong catalogue version')
    for field in ('target','evidence_scope'):
        if not isinstance(report.get(field),str) or not report[field].strip(): raise ValueError('Missing '+field)
    timestamp(report.get('assessed_at'))
    expected=[x['id'] for x in catalog['controls']]
    checks=report.get('checks',[])
    if not isinstance(checks,list) or any(not isinstance(c,dict) for c in checks): raise ValueError('Invalid checks')
    ids=[c.get('id') for c in checks]
    if ids!=expected: raise ValueError('Missing, duplicated, reordered or unexpected control IDs')
    for c in checks:
        if c.get('status') not in STATUSES: raise ValueError(c['id']+': invalid status')
        if not isinstance(c.get('rationale'),str) or not c['rationale'].strip(): raise ValueError(c['id']+': rationale required')
        evidence=c.get('evidence')
        if not isinstance(evidence,list): raise ValueError(c['id']+': evidence must be a list')
        if c['status'] in ('PASS','FAIL','WARN') and not evidence: raise ValueError(c['id']+': observation without evidence')
        for e in evidence:
            if not isinstance(e,dict): raise ValueError(c['id']+': invalid evidence')
            for f in ('source','observation','method'):
                if not isinstance(e.get(f),str) or not e[f].strip(): raise ValueError(c['id']+': missing evidence '+f)
            timestamp(e.get('observed_at'))
        if c['status']=='N/A' and (not c.get('na_reason') or not c.get('na_approver')):
            raise ValueError(c['id']+': N/A needs an applicability reason and approver')
        if c.get('exception'):
            exception=c['exception']
            if not isinstance(exception,dict) or any(not exception.get(k) for k in ('owner','approver','reason','compensating_control','expires_at')):
                raise ValueError(c['id']+': incomplete exception')
            timestamp(exception['expires_at'])
            if c['status']=='PASS': raise ValueError(c['id']+': an exception cannot create a PASS')
    counts={s:sum(c['status']==s for c in checks) for s in STATUSES}
    denominator=len(expected)-counts['N/A']
    numerator=sum(counts[s] for s in ('PASS','FAIL','WARN'))
    return dict(baseline_version=catalog['version'],counts=counts,applicable=denominator,evidenced=numerator,coverage_percent=round(100*numerator/denominator,1) if denominator else None)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--catalog',required=True);p.add_argument('report');args=p.parse_args()
    try:
        summary=validate(json.loads(Path(args.catalog).read_text()),json.loads(Path(args.report).read_text()))
        print(json.dumps(summary,indent=2));return 0
    except (OSError,ValueError,KeyError,TypeError) as error:
        print('ERROR: '+str(error),file=sys.stderr);return 2
if __name__=='__main__':sys.exit(main())
