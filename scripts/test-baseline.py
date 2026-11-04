#!/usr/bin/env python3
"""Regression tests for misleading baseline success and inventory blind spots."""
import json, os, stat, subprocess, sys, tempfile
from pathlib import Path
script = Path(__file__).with_name('baseline.py')
with tempfile.TemporaryDirectory(prefix='ch-baseline-test-') as tmp:
    root = Path(tmp)
    watched = root/'watched'; watched.mkdir()
    config = watched/'config'; config.write_text('approved\n')
    paths = root/'paths.json'; paths.write_text(json.dumps([str(watched)]))
    manifest = root/'baseline.json'
    def call(op, expected):
        p = subprocess.run([sys.executable, str(script), op, '--paths', str(paths), '--manifest', str(manifest)], capture_output=True, text=True)
        assert p.returncode == expected, (op, p.returncode, expected, p.stdout, p.stderr)
        return p
    call('create', 0); saved = manifest.read_bytes()
    assert stat.S_IMODE(manifest.stat().st_mode) == 0o600
    call('check', 0); print('PASS | clean inventory and private manifest')
    paths.write_text(json.dumps([str(watched), str(root/'missing')]))
    call('create', 2); assert manifest.read_bytes() == saved
    print('PASS | missing input leaves existing manifest byte-identical')
    paths.write_text(json.dumps([str(watched)]))
    config.write_text('drift\n'); assert 'sha256' in call('check', 1).stdout
    config.write_text('approved\n'); call('check', 0); print('PASS | content drift and restoration')
    added = watched/'extra.conf'; added.write_text('unexpected\n')
    assert 'ADDED' in call('check', 1).stdout; added.unlink(); print('PASS | unexpected drop-in detected')
    mode = stat.S_IMODE(config.stat().st_mode); config.chmod(0o600 if mode != 0o600 else 0o644)
    assert 'mode' in call('check', 1).stdout; config.chmod(mode); print('PASS | permission drift detected')
    if os.geteuid() == 0:
        uid, gid = config.stat().st_uid, config.stat().st_gid
        os.chown(config, 65534, gid); assert 'uid' in call('check', 1).stdout
        os.chown(config, uid, gid); print('PASS | ownership drift detected')
    config.unlink(); assert 'MISSING' in call('check', 1).stdout
    print('PASS | missing approved file detected')
    config.symlink_to(root/'outside'); assert 'kind' in call('check', 1).stdout
    config.unlink(); config.write_text('approved\n'); config.chmod(mode)
    call('check', 0); print('PASS | symlink substitution detected without reading its target')
    fifo = watched/'pipe'; os.mkfifo(fifo)
    call('create', 2); assert manifest.read_bytes() == saved; fifo.unlink()
    print('PASS | unsupported input cannot replace baseline')
    assert not list(root.glob('.baseline-*')); print('PASS | no partial manifest left behind')
