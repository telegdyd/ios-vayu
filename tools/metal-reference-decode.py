#!/usr/bin/env python3
"""WSL: decode a metal-reference-capture.py run with native Mesa cffdump."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture_dir', type=Path)
    parser.add_argument('--decoder', type=Path, default=Path.home() /
                        'vayu/xnu-deps/build/mesa/metal4-native-build/src/freedreno/decode/cffdump')
    args = parser.parse_args()
    results = []
    for entry in json.loads((args.capture_dir / 'manifest.json').read_text()):
        capture = args.capture_dir / entry['file']
        if hashlib.sha256(capture.read_bytes()).hexdigest() != entry['sha256']:
            raise RuntimeError('hash mismatch: ' + str(capture))
        output = capture.with_suffix('.decode.txt')
        errors = capture.with_suffix('.decode.stderr')
        with output.open('wb') as out, errors.open('wb') as err:
            result = subprocess.run([str(args.decoder), '--no-color', '--no-pager',
                                     str(capture)], stdout=out, stderr=err)
        text = output.read_text(errors='replace')
        if result.returncode or errors.stat().st_size or 'chip_id: 0x6040001' not in text:
            raise RuntimeError('decode failed or wrong chip: ' + str(capture))
        packets = {name: text.count(name) for name in (
            'CP_DRAW_INDX_OFFSET', 'CP_EXEC_CS', 'CP_BLIT', 'CP_SET_BIN_DATA5',
            'CP_EVENT_WRITE', 'CP_WAIT_FOR_IDLE')}
        results.append(dict(file=capture.name, case=entry['case'],
                            decoder_exit=result.returncode, packets=packets,
                            decode_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
                            stderr_bytes=errors.stat().st_size))
        print(capture.name, packets, flush=True)
    (args.capture_dir / 'decode-summary.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
