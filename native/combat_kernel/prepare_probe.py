#!/usr/bin/env python3
"""Prepare an isolated native-physics experiment; never alter the game dispatch."""
import argparse
import json
import shutil
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1] / 'godot-game'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=PROJECT)
    args = parser.parse_args()
    source = args.project.resolve()
    extension = HERE / 'combat_kernel.gdextension'
    library = HERE / 'bin/libeagle_combat_kernel.macos.template_release.arm64.dylib'
    if not library.is_file():
        parser.error('Build the macOS arm64 library first; see README.md.')
    destination = Path(tempfile.mkdtemp(prefix='eagle-native-probe-'))
    for item in source.iterdir():
        target = destination / item.name
        if item.name in ['scripts', 'tests', '.godot']:
            shutil.copytree(item, target)
        elif item.is_dir():
            target.symlink_to(item, target_is_directory=True)
        else:
            shutil.copy2(item, target)
    project = destination / 'project.godot'
    text = project.read_text()
    assert text.count('[autoload]') == 1
    project.write_text(text.replace('[autoload]', '[autoload]\nCombatNativeProbe="*res://native_probe_loader.gd"'))
    (destination / 'native_probe_loader.gd').write_text(
        'extends Node\nfunc _init():\n'
        '\tvar result=GDExtensionManager.load_extension(' + json.dumps(str(extension)) + ')\n'
        '\tassert(result==GDExtensionManager.LOAD_STATUS_OK or result==GDExtensionManager.LOAD_STATUS_ALREADY_LOADED)\n'
        '\tassert(ClassDB.class_exists("EagleCombatKernel"))\n'
        '\tprint("Eagle native kernel loaded")\n'
    )
    physics = destination / 'scripts/tactical/soldier_physics.gd'
    text = physics.read_text()
    assert 'native_kernel' not in text
    text = text.replace('extends RefCounted', 'extends RefCounted\nstatic var native_kernel\nstatic var native_calls=0', 1)
    text = text.replace('\tr.Soldiers.prepare_neighbours(r,rows,elapsed)', '\tvar fastest: float=r.config.individual_charge.speed*2.\n\tfor u in r.units:fastest=maxf(fastest,(u.combat_stats if u.has(\'combat_stats\') else r.config.types[u.kind]).speed*r.powers.speed_multiplier(u)*1.35)')
    start = text.index('\tfor i in rows.size():', text.index('\tvar before=points.duplicate()'))
    end = text.index('\tfor row in rows:', start)
    text = text[:start] + (
        '\tif native_kernel==null:native_kernel=ClassDB.instantiate("EagleCombatKernel")\n'
        '\tvar solved: Dictionary=native_kernel.repel(points,radii,headings,flags,sides,fastest,elapsed,r.repulsion_seed)\n'
        '\tpoints=solved.points;r.repulsion_seed=solved.seed;native_calls+=1\n'
    ) + text[end:]
    physics.write_text(text)
    test = destination / 'tests/tactical/test_packed_repulsion.gd'
    text = test.read_text()
    assert text.count("\tprint('Packed repulsion:") == 1
    test.write_text(text.replace("\tprint('Packed repulsion:", "\tcheck(Physics.native_calls>0,'Native kernel was actually exercised')\n\tprint('Packed repulsion:"))
    print(json.dumps({'probe_project': str(destination), 'source_project': str(source), 'extension': str(extension)}))


if __name__ == '__main__':
    main()
