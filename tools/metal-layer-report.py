#!/usr/bin/env python3
"""metal-layer-report.py APP_OUTPUT KERNEL_LOG [JSON_OUT]: task 10's run, judged from both sides.

APP_OUTPUT is what `metal_test layer` printed (its checks, intervals, "drawable IOSurface IDs:"); KERNEL_LOG the phone's
log over the same time (devices/poco-x3-pro/tools/sweet-netlog.py), which holds SpringBoard's MetalLayerHost lines and
the framebuffer's (MiniIOMobileFramebuffer) and window server's (hakios-gl) statistics. Between "context N hosted" and
"nothing hosted" it counts:

  - swaps whose framebuffer layers name one of the program's drawables (the drawable scanned out as it is) and the
    other surfaces they name;
  - the framebuffer's per-period counters: surfaces given to the GPU again while they were copied to the panel, locked
    for drawing while copied (either would be tearing), swaps the GPU had not finished after 20 ms ("copied as it is");
  - the panel's frames a second (S5FPS) and its frame-to-frame lines;
  - with LAYER_PLAIN=1 (the Metal layer half the screen, so the window server composites it), the program's own reads
    of the window server's composited surfaces: this program's background on a quarter of the grid at least, and all of
    it from one frame (a torn composition mixes two frame numbers).

Prints a summary and, with JSON_OUT, writes it. Exit status 1 if a check fails.
"""
import json
import re
import sys


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    app = open(sys.argv[1], encoding='utf-8', errors='replace').read()
    log = open(sys.argv[2], 'rb').read().decode('utf-8', 'replace').splitlines()

    m = re.search(r'drawable IOSurface IDs:([ 0-9]*)', app)
    ours = set(int(x) for x in m.group(1).split()) if m else set()
    checks = re.findall(r'^metal_layer: (PASS|FAIL) (.*)$', app, re.M)
    run = re.search(r'^metal_layer: the run: .*$', app, re.M)
    whole = re.search(r'^metal_layer:   present interval \(whole run\): (.*)$', app, re.M)
    gpu = re.findall(r'^metal_layer:   GPU time \(plug-in\'s GPUStart/EndTime\): (.*)$', app, re.M)

    start = end = None
    for i, line in enumerate(log):
        if re.search(r'MetalLayerHost: context \d+ hosted', line) and not line.startswith('1970'):
            start, end = i, None
        elif 'MetalLayerHost: nothing hosted' in line and start is not None and not line.startswith('1970'):
            end = i
    if start is None or end is None:
        sys.exit('no "hosted" ... "nothing hosted" span in the kernel log')
    span = log[start:end]

    swaps = scanned = 0
    others = {}
    regiven = locked = late = 0
    fps, f2f = [], []
    shown = 0
    for line in span:
        s = re.search(r'swap #\d+: surfaces in layers 0x[0-9a-f]+ now \(0x[0-9a-f]+ before\): ([0-9 ]+)', line)
        if s:
            ids = [int(x) for x in s.group(1).split() if x != '0']
            swaps += 1
            scanned += any(i in ours for i in ids)
            for i in ids:
                if i not in ours:
                    others[i] = others.get(i, 0) + 1
        f = re.search(r'fences: \d+ swaps .*?; (\d+) surfaces were given to the GPU again while they were copied; (\d+) were locked', line)
        if f:
            regiven += int(f.group(1))
            locked += int(f.group(2))
        late += 'the frame is copied as it is' in line
        p = re.search(r'S5FPS: (\d+) ms: (\d+) frames', line)
        if p:
            fps.append(round(int(p.group(2)) * 1000 / int(p.group(1)), 1))
        if 'from one frame to the next:' in line:
            f2f.append(line.split('from one frame to the next: ', 1)[1])
        shown += bool(re.search(r'IOSurface shown, .* 1125 x 2436', line))

    # the first and last second are partial (hosting starts and stops in them)
    inner = fps[1:-1] if len(fps) > 2 else fps
    summary = {
        'drawable_surfaces': sorted(ours),
        'app_checks': {'pass': sum(c[0] == 'PASS' for c in checks), 'fail': [c[1] for c in checks if c[0] == 'FAIL']},
        'app_run': run.group(0) if run else None,
        'app_present_interval': whole.group(1) if whole else None,
        'app_gpu_time_periods': gpu,
        'kernel_log_lines_hosted': len(span),
        'framebuffer_swaps_naming_layers': swaps,
        'swaps_with_a_drawable_in_a_layer': scanned,
        'other_surfaces_in_layers': others,
        'surfaces_given_to_gpu_while_copied': regiven,
        'surfaces_locked_while_copied': locked,
        'swaps_copied_before_gpu_done': late,
        'panel_frames_per_second': fps,
        'panel_frame_to_frame': f2f,
        'window_server_new_display_sized_surface_textures': shown,
    }
    # how the panel got the frames: the drawable itself in a framebuffer layer (an opaque full-screen layer), or the
    # window server's composition of it (LAYER_PLAIN=1), which the program read back from the window server's surfaces
    comp = re.findall(r'^metal_layer: composited frame at frame (\d+): .*? the best, IOSurface \d+: (\d+) of (\d+) grid points'
                      r'.*?from (\d+) frame number\(s\):([ 0-9]*)', app, re.M)
    torn = 'MIXED frames' in app
    composited = [{'at': int(c[0]), 'points': int(c[1]), 'of': int(c[2]), 'frames': [int(x) for x in c[4].split()]} for c in comp]
    summary['composited_captures'] = composited
    plain = 'LAYER_PLAIN' in app
    summary['mode'] = 'composited (LAYER_PLAIN)' if plain else 'full screen'
    reached = (all(c['points'] * 4 >= c['of'] and len(c['frames']) >= 1 for c in composited) and composited and not torn) if plain         else scanned > 0
    ok = (not summary['app_checks']['fail'] and reached and regiven == 0 and locked == 0 and late == 0 and inner
          and min(inner) >= 50)
    summary['verdict'] = 'PASS' if ok else 'FAIL'
    for k, v in summary.items():
        print(f'{k}: {v}')
    if len(sys.argv) > 3:
        json.dump(summary, open(sys.argv[3], 'w'), indent=1)
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
