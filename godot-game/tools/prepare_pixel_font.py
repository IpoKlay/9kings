"""Normalize the supplied CC0 pixel fonts for the game's existing UI typography.

Offline tool only: requires fontTools. Glyph outlines are unchanged; adjusting the
em scales advances and vertical metrics together, unlike a glyph-only transform.
"""
import argparse
from pathlib import Path
from fontTools.ttLib import TTFont

parser = argparse.ArgumentParser(description=__doc__)
variant = parser.add_mutually_exclusive_group()
variant.add_argument('--italic', action='store_true', help='Prepare Monogram Italic.')
variant.add_argument('--m5x7', action='store_true', help='Prepare m5x7.')
args = parser.parse_args()
suffix = '-italic' if args.italic else ''
style = 'Medium' if args.m5x7 else 'Italic' if args.italic else 'Regular'
family = 'm5x7 Eagle' if args.m5x7 else 'Monogram Eagle'
source = 'm5x7.ttf' if args.m5x7 else f'monogram-extended{suffix}.ttf'
destination = 'm5x7-eagle.ttf' if args.m5x7 else f'monogram-eagle{suffix}.ttf'
fonts = Path(__file__).resolve().parents[1] / 'assets' / 'fonts'
font = TTFont(fonts / source)
font['head'].unitsPerEm = 640  # Original 1024: match the CJK companion's visual size.
names = {1: family, 2: style, 3: f'{family} {style} 1.0',
         4: f'{family} {style}', 6: f'{family.replace(" ", "")}-{style}',
         16: family, 17: style}
for entry in font['name'].names:
    if entry.nameID in names:
        entry.string = names[entry.nameID].encode(entry.getEncoding())
font.save(fonts / destination)
