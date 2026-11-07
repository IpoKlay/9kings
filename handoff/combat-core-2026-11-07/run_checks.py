#!/usr/bin/env python3
"""Reproduce maintained combat checks from any checkout. Uses Python standard library."""
import argparse
import json
import re
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=shutil.which('godot') or shutil.which('Godot'))
    parser.add_argument('--suite', action='append', help='Run only a named suite; repeat for several.')
    parser.add_argument('--import-first', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT / 'output/combat-core-2026-11-07/checks/source')
    args = parser.parse_args()
    if not args.godot:
        parser.error('Pass --godot /absolute/path/to/Godot (version 4.7.2).')
    project = ROOT / 'godot-game'
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    (ROOT / 'output/sword-banner-reference').mkdir(parents=True, exist_ok=True)
    catalogue = json.loads((HERE / 'suites.json').read_text())
    suites = args.suite or catalogue['suites']
    if any(s not in catalogue['suites'] for s in suites):
        parser.error('Unknown suite. See suites.json; known legacy failures are intentionally separate.')
    if args.import_first:
        with (out / 'import.log').open('w') as log:
            result = subprocess.run([args.godot, '--headless', '--path', str(project), '--editor', '--import'], stdout=log, stderr=subprocess.STDOUT, timeout=600)
        if result.returncode:
            raise SystemExit('Resource import failed; inspect import.log.')
    rows = []
    for name in suites:
        cmd = [args.godot, '--headless', '--path', str(project), '--script', f'res://tests/tactical/test_{name}.gd']
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            text = result.stdout + result.stderr
            code = result.returncode
        except subprocess.TimeoutExpired as exc:
            text = str(exc); code = -1
        (out / (name + '.log')).write_text(text)
        warnings = [s for s in text.splitlines() if 'ObjectDB' in s or 'resources still in use' in s or 'ret != noErr' in s]
        errors = [s for s in text.splitlines() if ('SCRIPT ERROR' in s or s.startswith('ERROR:')) and s not in warnings]
        summaries = [s for s in text.splitlines() if re.search(r'checks|failures|PASS|FAIL', s)]
        passed = code == 0 and not errors and bool(summaries)
        if any(re.search(r'\b[1-9]\d* failures\b(?![=:])|\bfailures=[1-9]\d*', s) for s in summaries):
            passed = False
        rows.append({'suite': name, 'exit': code, 'passed': passed, 'errors': errors, 'warnings': warnings, 'summary': summaries})
        (out / 'results.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
        print(name, 'PASS' if passed else 'FAIL', summaries[-1:] or errors, flush=True)
    raise SystemExit(0 if all(row['passed'] for row in rows) else 1)

if __name__ == '__main__':
    main()
