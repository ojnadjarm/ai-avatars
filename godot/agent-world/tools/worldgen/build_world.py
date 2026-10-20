#!/usr/bin/env python3
"""World spec -> DIR/{scene.json, art/, world.tscn} through the pixel-scene skill, T715 pixel-foliage (world_foliage.py),
raised terraces (terrace.py) and tools/worldgen/export_world.gd. usage: build_world.py SPEC.json --out DIR"""
import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import time

P = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SKILL = os.path.expanduser(os.environ.get('PIXEL_SCENE', '~/.claude/skills/pixel-scene/scripts'))
sys.path.insert(0, SKILL)
import placers  # noqa: E402
import terrace  # noqa: E402
import world_foliage  # noqa: E402
RETIRED = os.path.expanduser('~/agent-work/research/2026-10-19/T714/retired-assets')
GENERATED = ('scene.json', 'art', 'world.tscn')


def stage(name, t0):
    print(f'STAGE {name} {time.time() - t0:.1f}s', flush=True)
    return time.time()


def run(cmd):
    """Run a command, echo its output, return (exit code, output)."""
    r = subprocess.run(cmd, capture_output=True, text=True)
    out = r.stdout + r.stderr
    print(out.rstrip())
    return r.returncode, out


def use_day_albedo(art, built):
    """Point every foliage albedo from <n>_night.png to its day twin listed in the plant's json files.day; no moon glitter."""
    n = 0
    for node in built['nodes']:
        alb = node['files'].get('albedo', '')
        if not alb.endswith('_night.png'):
            continue
        meta = os.path.join(art, alb[:-len('_night.png')] + '.json')
        day = json.load(open(meta))['files']['day'] if os.path.isfile(meta) else None
        if not day or not os.path.isfile(os.path.join(art, day)):
            sys.exit(f'FAIL no day twin for {alb}')
        node['files']['albedo'] = day
        n += 1
    built['motes'] = False
    built['moon_reflect'] = None
    print(f'DAY albedo swapped on {n} plants, motes off')


def build_scene(scene_path, tmp):
    """pixel-scene build.py in process, its foliage placer swapped for the T715 one (plants.py atlases, no sway maps)."""
    import build
    placers.PFPlacer = world_foliage.Placer
    build.main(scene_path, tmp)


def run_extras(art, built, spec, extras):
    """Each extras entry {module, fn, at, ...} calls fn(graph, entry, spec); its nodes/collide/lights/emit join built."""
    import graph
    import terrain
    top = terrain.plateau(spec, *spec['size'])[0] if spec.get('cliff') else None
    for k, e in enumerate(extras):
        path = os.path.join(P, e['module'])
        mod_spec = importlib.util.spec_from_file_location(f'world_extras_{k}', path)
        mod = importlib.util.module_from_spec(mod_spec)
        mod_spec.loader.exec_module(mod)
        g = graph.Graph(art, top)
        res = getattr(mod, e['fn'])(g, e, spec) or {}
        for key, items in (('nodes', g.nodes), ('collide', g.collide), ('lights', g.lights), ('emit', g.emit)):
            built[key].extend(items + list(res.get(key, [])))
        print(f'EXTRAS {e["module"]}:{e["fn"]} nodes {len(g.nodes)} collide {len(g.collide)} lights {len(g.lights)}')


def retire(path):
    """Move an old file or folder to the T714 retired-assets tree (same path under P), never delete it."""
    rel = os.path.relpath(path, P) if path.startswith(P + os.sep) else os.path.relpath(path, os.path.expanduser('~'))
    dst = os.path.join(RETIRED, rel)
    if os.path.exists(dst):
        dst += time.strftime('.%Y%m%d-%H%M%S')
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.move(path, dst)
    print(f'RETIRED {rel}')


def swap(tmp, out):
    """Replace DIR with DIR.tmp: keep world.json, drop the previous generated build, retire any other old file."""
    if os.path.isdir(out):
        ours = os.path.isfile(os.path.join(out, 'art', 'built.json'))
        for name in os.listdir(out):
            path = os.path.join(out, name)
            if name == 'world.json':
                continue
            if ours and name in GENERATED:
                shutil.rmtree(path) if os.path.isdir(path) else os.remove(path)
            else:
                retire(path)
    os.makedirs(out, exist_ok=True)
    for name in os.listdir(tmp):
        shutil.move(os.path.join(tmp, name), os.path.join(out, name))
    os.rmdir(tmp)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('spec')
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    spec_path, out = os.path.abspath(a.spec), os.path.abspath(a.out).rstrip('/')
    tmp = out + '.tmp'
    t_all = t0 = time.time()
    spec = json.load(open(spec_path))
    game = spec.pop('game', {})
    if os.path.isdir(tmp):
        shutil.rmtree(tmp)
    art = os.path.join(tmp, 'art')
    os.makedirs(tmp)
    scene_path = os.path.join(tmp, 'scene.json')
    json.dump(spec, open(scene_path, 'w'), indent=1)
    t0 = stage('scene', t0)
    build_scene(scene_path, tmp)
    t0 = stage('build', t0)
    built_path = os.path.join(art, 'built.json')
    built = json.load(open(built_path))
    built['day'] = bool(game.get('day', False))
    built['glow'] = bool(game.get('glow', True))
    if built['day']:
        use_day_albedo(art, built)
    run_extras(art, built, spec, game.get('extras', []))
    terrace.build(art, built, spec, game)
    world_foliage.finish(built, art)
    json.dump(built, open(built_path, 'w'), indent=1)
    t0 = stage('day+extras', t0)
    code, out_txt = run([sys.executable, os.path.join(SKILL, 'reach.py'), scene_path, tmp])
    if code:
        print('\n'.join(ln for ln in out_txt.splitlines() if ln.endswith(': NO')))
        sys.exit('FAIL walker cannot reach every goal')
    t0 = stage('reach', t0)
    code, out_txt = run(['godot', '--headless', '--audio-driver', 'Dummy', '--path', P, '-s',
                         'tools/worldgen/export_world.gd', '--', tmp, spec_path])
    if code or 'EXPORT ok' not in out_txt or not os.path.isfile(os.path.join(tmp, 'world.tscn')):
        sys.exit(f'FAIL export_world.gd exit {code}')
    t0 = stage('export', t0)
    swap(tmp, out)
    stage('swap', t0)
    print(f'WORLD {out} built in {time.time() - t_all:.1f}s')


if __name__ == '__main__':
    main()
