extends RefCounted
## Coordinates are relative to the front rank, then centered on the regiment.
const NAMES = {'default':'方阵', 'wedge':'楔形阵', 'ring':'组合外环', 'scatter':'散阵', 'testudo':'龟甲阵', 'dense':'密集阵', 'ring_inner':'组合内环', 'free':'自由攻击'}
const SELECTABLE = ['default','wedge','ring','scatter','testudo','dense']
const OPTIONS = {
	'spear':['default','ring','scatter'],
	'shield':['default','testudo','ring','scatter'],
	'cavalry':['default','wedge'], 'archer':['default','dense','scatter']}

static func offsets(count: int, form: String, radius: float = 175.0) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var spacing = 29.0 * (1.65 if form == 'scatter' else 0.78 if form in ['dense','testudo'] else 1.0)
	var rank = 0
	while points.size() < count:
		var width = mini(rank + 1 if form == 'wedge' else 7, count - points.size())
		for column in width:
			var p = Vector2((column - (width - 1) * 0.5) * spacing, rank * spacing)
			if form == 'scatter': p.x += spacing * (0.22 if rank % 2 else -0.22)
			if form in ['ring','ring_inner']: p = Vector2.from_angle(TAU * points.size() / count) * radius
			points.append(p)
		rank += 1
	var center = Vector2.ZERO
	for p in points: center += p
	center /= maxi(1, count)
	for i in points.size(): points[i] -= center
	return points

static func world_offset(offset: Vector2, heading: Vector2) -> Vector2:
	return Vector2(-heading.y, heading.x) * offset.x - heading * offset.y

static func modifiers(form: String) -> Dictionary:
	match form:
		'wedge': return {'attack':0.0, 'armor':0.0, 'speed':1.0, 'rate':1.0, 'area':1.0, 'rain':0.0}
		'ring': return {'attack':-0.25, 'armor':0.6, 'speed':1.0, 'rate':1.0, 'area':1.0, 'rain':0.0}
		'ring_inner': return {'attack':0.0, 'armor':0.6, 'speed':1.0, 'rate':1.3, 'area':1.0, 'rain':0.0}
		'testudo': return {'attack':0.0, 'armor':1.8, 'speed':0.38, 'rate':1.0, 'area':1.0, 'rain':0.0}
		'scatter': return {'attack':0.0, 'armor':0.0, 'speed':1.18, 'rate':1.0, 'area':0.5, 'rain':0.0}
		'dense': return {'attack':-0.25, 'armor':0.0, 'speed':0.9, 'rate':1.0, 'area':1.0, 'rain':0.6}
	return {'attack':0.0, 'armor':0.0, 'speed':1.0, 'rate':1.0, 'area':1.0, 'rain':0.0}
