"""Pack the verified preview ZIP into nearest-neighbor battle pages.

After packing, run paint_cavalry_lighting.gd to apply the approved coat lighting.
"""

import argparse
from colorsys import hsv_to_rgb, rgb_to_hsv
from io import BytesIO
import json
from pathlib import Path
from zipfile import ZipFile

from PIL import Image, ImageChops


MAX_PAGE = 1024
BOW_TIPS = [[3, -28], [12, -28], [12, -33], [6, -35], [-3, -34], [-12, -34], [-11, -32], [-8, -33]]
PROJECT = Path(__file__).resolve().parents[1]
BASE_ROSTER = ('U01', 'U02', 'U03', 'U08', 'U13', 'U18', 'U23')

# Planted full-sprite poses in battle bearing order.
CAVALRY_PLANTED = {
    'U18': [0, 6, 5, 0, 0, 5, 5, 0],
    'U19': [10, 5, 4, 5, 4, 10, 10, 5],
    'U20': [5, 10, 0, 10, 10, 10, 9, 10],
    'U21': [5, 10, 10, 10, 10, 9, 10, 10],
    'U22': [0, 5, 0, 5, 0, 10, 0, 10],
    'U23': [0, 10, 0, 0, 0, 10, 5, 5],
}

def charge_motion(unit, clips, images):
    result = []
    for (frames, _), plant in zip(clips, CAVALRY_PLANTED[unit], strict=True):
        assert 0 <= plant < len(frames)
        poses = []
        for index, ax, ay in frames:
            frame = images[index]
            registered = Image.new('RGB', (128, 128), (36, 48, 42))
            registered.paste(frame, (64 - ax, 92 - ay), frame)
            poses.append(registered)

        # Register the saddle/upper barrel; legs, hooves, tail and weapon remain free to move.
        left, top, right, bottom = (54, 54, 74, 74)
        reference = poses[0].crop((left, top, right, bottom))
        offsets = []
        for pose in poses:
            def difference(dx, dy):
                crop = pose.crop((left + dx, top + dy, right + dx, bottom + dy))
                histogram = ImageChops.difference(reference, crop).histogram()
                return sum((index % 256) * count for index, count in enumerate(histogram))

            base = difference(0, 0)
            score, dx, dy = min((difference(x, y) + 450 * (abs(x) + abs(y)), x, y)
                                for x in range(-4, 5) for y in range(-4, 5))
            if score > .93 * base:
                dx, dy = 0, 0
            # Keep up to two pixels of natural bob and never move a frame more than two.
            offsets.append([max(0, abs(value) - 2) * (1 if value > 0 else -1) for value in (dx, dy)])
        result.append({'plant': plant, 'anchor_offsets': offsets})
    return result


def enemy_palette(image):
    # Existing enemy banners use blue. Shift the red cloth and paint while keeping
    # warm leather, skin, gold, transparent margins, and the original silhouette.
    palette = {}
    for _, color in image.getcolors(image.width * image.height):
        r, g, b, a = color
        hue, saturation, value = rgb_to_hsv(r / 255, g / 255, b / 255)
        if a and saturation > .32 and (hue < .047 or hue > .96):
            blue = hsv_to_rgb(.59, saturation * .76, min(1., value * 1.03))
            palette[color] = (*[round(channel * 255) for channel in blue], a)
        else:
            palette[color] = color
    result = Image.new('RGBA', image.size)
    result.putdata([palette[color] for color in image.get_flattened_data()])
    return result


def pack_page(archive, unit, action, clips, directions, path, cavalry_motion):
    sheet = Image.open(BytesIO(archive.read(f'assets/{unit}/{action}.png'))).convert('RGBA')
    images, unique, packed_clips = [], {}, []
    for bearing, direction in enumerate(directions):
        clip = clips[direction]
        frames = []
        for x, y, w, h in clip['rects']:
            frame = sheet.crop((x, y, x + w, y + h))
            left, top, right, bottom = frame.getbbox()
            frame = frame.crop((left, top, right, bottom))
            key = (frame.size, frame.tobytes())
            if key not in unique:
                unique[key] = len(images)
                images.append(frame)
            ax, ay = clip['anchor']
            frames.append((unique[key], ax - left, ay - top))
        timing = {'ms': clip['ms']}
        if clip.get('hit_frame') is not None:
            timing['hit_frame'] = clip['hit_frame']
        if action == 'attack' and 13 <= int(unit[1:]) <= 17:
            timing['release_offset'] = clip.get('release_offset', BOW_TIPS[bearing])
        packed_clips.append((frames, timing))

    if action == 'charge':
        cavalry_motion[unit] = charge_motion(unit, packed_clips, images)

    boxes = {}
    x = y = row = used_width = 0
    for index in sorted(range(len(images)), key=lambda i: -images[i].height):
        image = images[index]
        w, h = image.size
        assert w + 2 <= MAX_PAGE and h + 2 <= MAX_PAGE
        if x + w + 2 > MAX_PAGE:
            x, y, row = 0, y + row, 0
        boxes[index] = [x + 1, y + 1, w, h]
        x += w + 2
        row = max(row, h + 2)
        used_width = max(used_width, x)
    assert y + row <= MAX_PAGE, (unit, action)
    atlas = Image.new('RGBA', (used_width, y + row))
    for i, frame in enumerate(images):
        px, py, w, h = boxes[i]
        atlas.paste(frame, (px, py))
        assert atlas.crop((px, py, px + w, py + h)).tobytes() == frame.tobytes()
    path.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(path, optimize=True)
    if unit in BASE_ROSTER:
        enemy_palette(atlas).save(path.with_name(action + '-enemy.png'), optimize=True)
    return [
        dict(timing, frames=[boxes[index] + [ax, ay] for index, ax, ay in frames])
        for frames, timing in packed_clips
    ], atlas.width * atlas.height * 4


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('verified_zip', type=Path)
    args = parser.parse_args()
    units, bytes_by_unit, cavalry_motion = {}, {}, {}
    with ZipFile(args.verified_zip) as archive:
        verification = json.loads(archive.read('verification.json'))
        coverage = verification['coverage']
        assert verification['total_visible_clips'] == 968
        assert not coverage['flagged_legacy_directions'] and not coverage['missing_animated_directions']
        roster = json.loads(archive.read('assets/roster.json'))
        assert roster['directions'] == ['south', 'south-east', 'east', 'north-east',
                                        'north', 'north-west', 'west', 'south-west']
        for unit, actions in roster['units'].items():
            units[unit], bytes_by_unit[unit] = {}, 0
            for action, clips in actions.items():
                path = PROJECT / 'assets/strategy/unit-animations' / unit / (action + '.png')
                units[unit][action], size = pack_page(archive, unit, action, clips, roster['directions'], path, cavalry_motion)
                bytes_by_unit[unit] += size
    assert len(units) == 23 and sum(len(actions) for actions in units.values()) * 8 == 968
    manifest = PROJECT / 'data/generated/approved_unit_animations.json'
    manifest.write_text(json.dumps(units, separators=(',', ':')) + '\n')
    motion_path = manifest.with_name('approved_cavalry_motion.json')
    motion_path.write_text(json.dumps(cavalry_motion, separators=(',', ':')) + '\n')
    print('All atlas pages (RGBA8): %.2f MiB' % (sum(bytes_by_unit.values()) / 1048576))
    base_size = sum(bytes_by_unit[u] for u in BASE_ROSTER)
    max_allies = base_size
    for index in range(1, 5):
        ids = ['U01', 'U02', f'U{3+index:02}', f'U{8+index:02}', f'U{13+index:02}', f'U{18+index:02}', 'U23']
        max_allies = max(max_allies, sum(bytes_by_unit[u] for u in ids))
    print('One team at level 1 (RGBA8): %.2f MiB' % (base_size / 1048576))
    print('Upper bound for active allied level plus level 1 enemies (RGBA8): %.2f MiB' %
          ((max_allies + base_size) / 1048576))


if __name__ == '__main__':
    main()
