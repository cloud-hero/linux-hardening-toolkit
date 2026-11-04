#!/usr/bin/env python3
"""Explicit-scope file inventory. Create writes only a complete atomic manifest.

check is observational. Exit 0 = match, 1 = drift, 2 = input/collection error.
This is not tamper-proof attestation; authenticate the manifest independently.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile

SCHEMA = 'cloudhero-file-baseline/v1'

def roots_from_file(path):
    data = json.loads(Path(path).read_text())
    if not isinstance(data, list) or not data:
        raise ValueError('Paths must be a nonempty JSON list of absolute paths')
    roots = []
    for item in data:
        if not isinstance(item, str) or not item.startswith('/') or '\n' in item or '\x00' in item:
            raise ValueError('Each path must be an absolute single-line string')
        value = os.path.normpath(item)
        if value == '/':
            raise ValueError('Refusing an unbounded whole-filesystem baseline')
        if value in roots:
            raise ValueError('Duplicate inventory root: ' + value)
        roots.append(value)
    for a in roots:
        for b in roots:
            if a != b and Path(a) in Path(b).parents:
                raise ValueError('Overlapping inventory roots: ' + a + ', ' + b)
    return sorted(roots)

def inventory(roots, allow_missing=False):
    result = {}
    def visit(path):
        try:
            info = path.lstat()
        except FileNotFoundError:
            if allow_missing:
                return
            raise
        entry = {'mode': stat.S_IMODE(info.st_mode), 'uid': info.st_uid, 'gid': info.st_gid}
        if stat.S_ISLNK(info.st_mode):
            entry.update(kind='symlink', target=os.readlink(path))
        elif stat.S_ISDIR(info.st_mode):
            entry['kind'] = 'directory'
            for child in sorted(path.iterdir()):
                visit(child)
        elif stat.S_ISREG(info.st_mode):
            digest = hashlib.sha256()
            # Refuse a final-component symlink substituted between lstat and open.
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            with os.fdopen(fd, 'rb') as handle:
                opened = os.fstat(handle.fileno())
                if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
                    raise ValueError('File changed during collection: ' + str(path))
                for chunk in iter(lambda: handle.read(1024 * 1024), b''):
                    digest.update(chunk)
                after = os.fstat(handle.fileno())
                if (opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                    raise ValueError('File changed during collection: ' + str(path))
            entry.update(kind='file', sha256=digest.hexdigest())
        else:
            raise ValueError('Unsupported special file: ' + str(path))
        result[str(path)] = entry
    for root in roots:
        visit(Path(root))
    return dict(sorted(result.items()))

def create(roots, target):
    target = Path(target).absolute()
    if target.is_symlink():
        raise ValueError('Manifest destination must not be a symlink')
    for root in roots:
        if target == Path(root) or Path(root) in target.parents:
            raise ValueError('Manifest must be outside all inventoried paths')
    # Fail before opening a new manifest if any mandatory input is absent/unreadable.
    data = {'schema': SCHEMA, 'roots': roots, 'entries': inventory(roots)}
    fd, temporary = tempfile.mkstemp(prefix='.baseline-', dir=target.parent)
    try:
        with os.fdopen(fd, 'w') as handle:
            os.fchmod(handle.fileno(), 0o600)
            json.dump(data, handle, indent=2, sort_keys=True)
            handle.write('\n'); handle.flush(); os.fsync(handle.fileno())
        os.replace(temporary, target)
        parent_fd = os.open(target.parent, os.O_RDONLY)
        try: os.fsync(parent_fd)
        finally: os.close(parent_fd)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
    print('CREATED:', len(data['entries']), 'entries; approve and retain the manifest digest independently')

def check(roots, target):
    expected = json.loads(Path(target).read_text())
    if expected.get('schema') != SCHEMA or expected.get('roots') != roots:
        raise ValueError('Manifest schema/scope differs from the independently supplied path list')
    old = expected.get('entries')
    if not isinstance(old, dict) or not old or any(not isinstance(v, dict) for v in old.values()):
        raise ValueError('Manifest entries are invalid or empty')
    # Require coverage of each explicit root even if a manifest was edited incorrectly.
    if any(root not in old for root in roots):
        raise ValueError('Manifest omits an explicit inventory root')
    new = inventory(roots, allow_missing=True)
    findings = []
    for name in sorted(old.keys() | new.keys()):
        if name not in old: findings.append(('ADDED', name))
        elif name not in new: findings.append(('MISSING', name))
        elif old[name] != new[name]:
            fields = sorted(k for k in old[name].keys() | new[name].keys() if old[name].get(k) != new[name].get(k))
            findings.append(('CHANGED ' + ','.join(fields), name))
    for state, name in findings: print(state + ': ' + name)
    if findings:
        print('DRIFT:', len(findings), 'entries'); return 1
    print('MATCH:', len(new), 'entries, including names/types/modes/owners/content'); return 0

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['create', 'check'])
    parser.add_argument('--paths', required=True)
    parser.add_argument('--manifest', required=True)
    args = parser.parse_args()
    try:
        roots = roots_from_file(args.paths)
        if args.operation == 'create': create(roots, args.manifest); return 0
        return check(roots, args.manifest)
    except (OSError, ValueError, TypeError) as error:
        print('ERROR: ' + str(error), file=sys.stderr); return 2

if __name__ == '__main__': sys.exit(main())
