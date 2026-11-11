extends RefCounted
## Whole-sprite frames for the strategy battle. Gameplay continues to own time and positions.
const ROOT = 'res://assets/strategy/unit-animations/'
const MANIFEST = 'res://data/generated/approved_unit_animations.json'
# The 1280×720 default window displays the 1920×1080 battle at 2/3 scale.
const DISPLAY_SCALE = 1.5
static var roster: Dictionary
static var clips: Dictionary
var pages: Dictionary

class Clip:
	var regions: Array[Rect2] = []
	var anchors: PackedVector2Array
	var end_ms: PackedInt32Array
	var duration_ms: int = 0
	var release_ms: int = -1
	var release_offset: Vector2

	func _init(data: Dictionary):
		for i in data.frames.size():
			var f: Array = data.frames[i]
			regions.append(Rect2(f[0], f[1], f[2], f[3]))
			anchors.append(Vector2(f[4], f[5]))
			if i == int(data.get('hit_frame', -1)):
				release_ms = duration_ms
			duration_ms += int(data.ms[i])
			end_ms.append(duration_ms)
		if data.has('release_offset'):
			release_offset = Vector2(data.release_offset[0], data.release_offset[1])

	func frame_at(ms: float) -> int:
		for i in end_ms.size():
			if ms < end_ms[i]:
				return i
		return end_ms.size() - 1

	func attack_frame(age: float, duration: float, release_age: float) -> int:
		if release_ms < 0 or release_age <= 0. or release_age >= duration:
			return frame_at(age / duration * duration_ms)
		var ms: float
		if age + .000001 < release_age:
			ms = age / release_age * release_ms
		else:
			ms = lerpf(release_ms, duration_ms, maxf(0., age - release_age) / (duration - release_age))
		return frame_at(ms)

static func clip(id: String, action: String, bearing: int) -> Clip:
	if roster.is_empty():
		roster = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var key = id + '/' + action
	if not clips.has(key):
		var directions: Array[Clip] = []
		for data in roster[id][action]:
			directions.append(Clip.new(data))
		clips[key] = directions
	return clips[key][bearing]

static func bearing_for(heading: Vector2) -> int:
	return posmod(roundi(atan2(heading.x, heading.y) / (PI / 4.)), 8)

func page(id: String, action: String, side: String) -> Texture2D:
	var key = id + '/' + action + ('-enemy' if side == 'enemy' else '')
	if not pages.has(key):
		pages[key] = load(ROOT + key + '.png')
	return pages[key]
