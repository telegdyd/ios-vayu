#!/usr/bin/env python3
"""Retrieve the selected compute submission without text decoding its bytes."""
import importlib.util
from pathlib import Path
import sys
p = Path(__file__).with_name('metal-reference-capture.py')
spec = importlib.util.spec_from_file_location('capture', p)
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
name = sys.argv[1]
if name not in ('before', 'after'): raise SystemExit(2)
data = module.remote('cat', '/private/var/tmp/metal6-shared-'+name+'.rd')
out = module.ROOT / ('logs/metal-step6/shared-'+name+'.rd')
out.write_bytes(data)
print(str(out)+': '+str(len(data))+' bytes')
