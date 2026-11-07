#!/usr/bin/env python3
"""Validate task-6 readback and resource-lifetime evidence."""
from pathlib import Path
import hashlib
import json
import re
ROOT = Path(__file__).resolve().parents[1]
LOGS = ROOT / 'logs/metal-step6'
files = ('full-first.txt', 'full-paused.txt', 'full-live.txt')
selected = []
groups = []
for filename in files:
    s = (LOGS / filename).read_text(encoding='utf-8', errors='replace')
    assert 'probe: FAIL' not in s and 'transport-audit: FAIL' not in s, filename
    runs = s.count('probe: compute-only finished; 0 failures')
    assert runs == (1 if filename == 'full-first.txt' else 3), filename
    assert len(re.findall(r'transport-audit: PASS handles=0 mappings=0 queues=0 calls=\d+ errors=0 close=0', s)) == runs, filename
    if 'first' not in filename:
        assert 'runner: PASS failures=0' in s and 'watchdog resumed' not in s, filename
    checks = s.count('probe: ok ')
    assert checks == 78 * runs
    assert 'probe: SKIP' not in s
    assert checks % runs == 0
    groups.append(dict(file=filename, runs=runs, checks=checks,
                       checks_per_run=checks//runs, compute_checks=70*runs,
                       first_iovas=re.findall(r'first_iova=(0x[0-9a-f]+)', s)))
    lines = [x for x in s.splitlines() if x.startswith(('probe:', 'runner:', 'transport-audit:', 'hakios-metal:'))]
    selected.extend(['# '+filename, *lines, ''])
query = (LOGS/'query.txt').read_text()
assert query.count('query: PASS') == 2 and 'query: FAIL' not in query
assert 'transport-audit: PASS handles=0 mappings=0 queues=0' in query
selected.extend(['# Additional texture-size fixture', query])
before = (LOGS/'shared-before.txt').read_text()
assert 'shared: FAIL right=992/1024 tail=64/64 status=4 error=' in before
selected.extend(['# Captured pre-fix regression (expected failure)', before])
health = (LOGS/'health.txt').read_text()
selected.extend(['# Final health', health])
(ROOT / 'docs/metal-step6-phone.log').write_text('\n'.join(selected).rstrip()+'\n', encoding='utf-8', newline='\n')
captures=[]
for name in ('before','after'):
    rd=LOGS/('shared-'+name+'.rd')
    decode=rd.with_suffix('.decode.txt')
    assert rd.with_suffix('.decode.stderr').stat().st_size == 0
    decoded=decode.read_text()
    assert 'chip_id: 0x6040001' in decoded and 'CP_EXEC_CS' in decoded
    captures.append(dict(file=rd.name, bytes=rd.stat().st_size,
                         sha256=hashlib.sha256(rd.read_bytes()).hexdigest(),
                         decode_sha256=hashlib.sha256(decode.read_bytes()).hexdigest()))
assert 'l[r2.x+256]' in (LOGS/'shared-after.decode.txt').read_text()
assert 'l[r2.x+256]' not in (LOGS/'shared-before.decode.txt').read_text()
front = (LOGS/'frontend-check-final.log').read_text()
assert 'reader-check: 456 modules, 456 identical to llvm-dis' in front
assert 'translate 321/456, ir3 321/456' in front
assert '255 agree with LLVM, 0 differ' in front
assert '71 exactly defined operations agree on every case, 0 differ' in front
assert '35 texture calls run: 35 returned exactly what was put there, 0 did not, 0 refused' in front
baseline = (LOGS/'softpipe-baseline.log').read_text()
fixed = (LOGS/'softpipe-fixed.log').read_text()
old_failures = re.findall(r'^WRONG\s+(.+)$', baseline, re.M)
new_failures = re.findall(r'^WRONG\s+(.+)$', fixed, re.M)
assert len(old_failures) == 10 and old_failures == new_failures
for output in (baseline, fixed):
    assert '37 exactly defined operations agree on every case, 10 differ' in output
    assert '612 cases in all' in output
build = (LOGS/'build-final.log').read_text()
assert '261 tests, 0 failed checks' in build and 'probe: 0 failures' in build
fixtures = (LOGS/'fixtures-final.log').read_text()
assert fixtures.count('FIXTURE PASS') == 11 and 'FIXTURE FAIL' not in fixtures
phi = (LOGS/'phi-check.log').read_text()
assert phi.count('PASS ') == 2
parts = [build, '# Native fixture generation', '\n'.join(x for x in fixtures.splitlines() if x.startswith('FIXTURE ')),
         '# Pointer provenance regression', phi, '# Full frontend check (exit 1: pre-existing softpipe arithmetic failures)', front,
         '# Baseline and current: identical failing operations and counts', '\n'.join(old_failures),
         '# Baseline summary', '\n'.join(x for x in baseline.splitlines() if x.startswith('intrincheck:') and '/tmp/' not in x),
         '# Current summary', '\n'.join(x for x in fixed.splitlines() if x.startswith('intrincheck:') and '/tmp/' not in x)]
(ROOT/'docs/metal-step6-build.log').write_text('\n'.join(line.rstrip() for line in '\n'.join(parts).splitlines()).rstrip()+'\n', encoding='utf-8', newline='\n')
summary = dict(run='metal-step6', groups=groups, final_full_runs=7,
               final_compute_checks=490, final_transport_checks=56,
               additional_query_checks=2, captures=captures,
               software_regression=dict(full_check_exit=1, baseline_softpipe_failures=old_failures, current_softpipe_failures=new_failures),
               fixtures=['end_only', 'fill_id', 'fill_id_air', 'tex_copy_air', 'tex_fill_air', 'tex_sample_gid_air', 'chain160_air', 'chain220_air', 'long_chain_air', 'pvt_fill_air', 'tg_arg_air', 'ptr_phi_air', 'tex_fill_h_air', 'tex_fill_arr_air', 'tex_fill_3d_air', 'tex_sample_wide_air', 'tex_size_h_air'],
               sha256={name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in
                       ('userland/obj/metal-probe', 'userland/obj/metal_transport_run', 'userland/obj/metal-query-probe')})
(ROOT / 'docs/metal-step6-summary.json').write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8', newline='\n')
print(json.dumps(groups, indent=2))
