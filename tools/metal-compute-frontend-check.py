#!/usr/bin/env python3
"""Regression: pointer phis carry offsets, and reject cross-resource merges."""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[1]
AIR = Path.home() / 'vayu/build/mesa-host/build/src/compiler/air/air2nir'
s = (ROOT/'hakios-metal/tools/kernels/ptr_phi.ll').read_text()
with tempfile.TemporaryDirectory(prefix='metal6-phi-') as tmp:
    for name, source, expected in (
        ('same-buffer', s, True),
        ('different-buffer', s.replace('%pb = getelementptr inbounds i32, ptr addrspace(1) %in,', '%pb = getelementptr inbounds i32, ptr addrspace(1) %out,'), False)):
        ll = Path(tmp)/(name+'.ll'); bc = ll.with_suffix('.bc')
        ll.write_text(source)
        subprocess.run(['llvm-as', str(ll), '-o', str(bc)], check=True)
        r = subprocess.run([str(AIR), str(bc)], capture_output=True, text=True)
        assert (r.returncode == 0) == expected, r.stdout+r.stderr
        if not expected: assert 'pointer phi merges different resources' in r.stderr, r.stderr
        print('PASS '+name+(': rejected cross-resource provenance' if not expected else ': branch and loop offsets translate'))
