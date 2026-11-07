#!/usr/bin/env python3
"""Validate/extract task-5 evidence without committing the phone's full console."""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LOGS = ROOT / 'logs/metal-step5'
selected = []
groups = []
for filename in ('console.txt', 'console-active.txt'):
    raw = (LOGS / filename).read_text(encoding='utf-8', errors='replace')
    start = raw.rfind('runner: mode=paused repetitions=10')
    assert start >= 0, filename
    block = raw[start:]
    end = [m.end() for m in re.finditer('runner: PASS failures=0', block)]
    assert len(end) == 2, filename
    block = block[:end[1]]
    assert not re.search(r'(probe: FAIL|transport-audit: FAIL|runner: FAIL|watchdog resumed)', block)
    parts = re.split(r'(?=runner: mode=)', block)[1:]
    assert len(parts) == 2
    for part in parts:
        mode = re.search(r'mode=(\w+)', part).group(1)
        assert part.count('probe: stopped after stage 4') == 10
        assert part.count('probe: 0 failures') == 10
        assert part.count('probe: ok ') == 80
        assert len(re.findall(r'transport-audit: PASS handles=0 mappings=0 queues=0 calls=\d+ errors=0 close=0', part)) == 10
        assert part.count('expected=stopped') == (4 if mode == 'paused' else 0)
        groups.append(dict(console=filename, mode=mode, runs=10, checks=80,
                           wired_pages=[int(x) for x in re.findall(r'wired_pages=(\d+)', part)],
                           first_iovas=re.findall(r'first_iova=(0x[0-9a-f]+)', part)))
    if filename == 'console-active.txt':
        assert re.search(r'S5FPS: .*? [1-9]\d* synthetic touch samples', parts[1])
    # These prefixes contain test/GPU evidence only, never unrelated daemon data.
    lines = [line for line in block.splitlines() if line.startswith((
        'runner:', 'probe:', 'transport-audit:', 'hakios-metal:',
        'HakiosGPU:', 'MiniIOMobileFramebuffer: S5FPS:'))]
    selected.extend([f'# {filename}: latest rc.jobs run', *lines, ''])

health = (LOGS / 'final-health.txt').read_text(encoding='utf-8')
assert 'runner: PASS failures=0' in health and 'probe: 0 failures' in health
assert 'transport-audit: PASS handles=0 mappings=0 queues=0' in health
assert 'probe: FAIL' not in health and 'transport-audit: FAIL' not in health
selected.extend(['# Final health check', health])
(ROOT / 'docs/metal-step5-phone.log').write_text('\n'.join(selected).rstrip() + '\n', encoding='utf-8', newline='\n')
build = (LOGS / 'build.log').read_text(encoding='utf-8')
assert '261 tests, 0 failed checks' in build and 'probe: 0 failures' in build
(ROOT / 'docs/metal-step5-build.log').write_text(build, encoding='utf-8', newline='\n')
hashes = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in (
    'userland/obj/metal-probe', 'userland/obj/metal_transport_run',
    'userland/rc.jobs.metal-transport')}
report = dict(run='metal-step5', groups=groups, repeated_runs=40,
              repeated_checks=320, final_health_runs=1, sha256=hashes)
(ROOT / 'docs/metal-step5-summary.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
print('PASS: 40 repeated hardware runs / 320 checks / 40 successful cleanup audits; final health run passed')
