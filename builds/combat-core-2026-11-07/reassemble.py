#!/usr/bin/env python3
"""Restore and verify the unmodified playtest ZIPs. Does not extract or run them."""
import hashlib
import json
from pathlib import Path

folder = Path(__file__).resolve().parent
manifest = json.loads((folder / 'manifest.json').read_text())
for entry in manifest['files']:
    target = folder / entry['name']
    if target.exists():
        if target.stat().st_size == entry['bytes'] and hashlib.sha256(target.read_bytes()).hexdigest() == entry['sha256']:
            print('Already verified:', target.name)
            continue
        raise SystemExit('Existing ZIP differs; move it aside before retrying: ' + str(target))
    temporary = target.with_suffix('.zip.partial')
    if temporary.exists():
        raise SystemExit('Partial ZIP exists; move it aside before retrying: ' + str(temporary))
    total = hashlib.sha256()
    with temporary.open('xb') as output:
        for part in entry['parts']:
            data = (folder / part['name']).read_bytes()
            if len(data) != part['bytes'] or hashlib.sha256(data).hexdigest() != part['sha256']:
                raise SystemExit('Missing or damaged part: ' + part['name'])
            output.write(data)
            total.update(data)
    if temporary.stat().st_size != entry['bytes'] or total.hexdigest() != entry['sha256']:
        raise SystemExit('Final ZIP checksum mismatch: ' + str(temporary))
    temporary.rename(target)
    print('Verified:', target)
