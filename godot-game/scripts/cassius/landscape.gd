extends Node2D

const Art = preload('res://scripts/tactical/approved_unit_art.gd')
const GRASS = preload('res://assets/environments/iberia-grass-ground.png')
const TREE = preload('res://assets/tree_3.png')
const FOREST = preload('res://assets/tree_0.png')
const STORE = preload('res://assets/strategy/pixellab-v2/B07.png')
const CAMP = preload('res://assets/building_legion_1.png')
const ALTAR = preload('res://assets/strategy/pixellab-v2/B01.png')
const LENGTH = 3100.0
const ROAD_Y = 405.0
const STOPS = {
	'village': Vector2(300,395), 'shop': Vector2(810,460),
	'camp': Vector2(1310,375), 'altar': Vector2(1790,465),
	'warning': Vector2(2280,408), 'fork': Vector2(2800,403),
}
var actor = Vector2(180,405)
var camera_x = 0.0
var facing = 2
var moving = false
var clock = 0.0
var walking = 0.0
var tint = Color('#9b8060')
var land = 'south'
var art = Art.new()
var trees: Array[Vector2] = []
var ritual = 0.0
var weather = true
var shown_markers = {}

func _ready():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var rng = RandomNumberGenerator.new()
	rng.seed = 16641
	for index in 54:
		var x = rng.randf_range(-100,LENGTH+150)
		var y = rng.randf_range(490,660) if index%3 == 0 else rng.randf_range(220,348)
		trees.append(Vector2(x,y))
	trees.sort_custom(func(a,b): return a.y < b.y)
	for id in ['U20','U02','U05','U10','U01']:
		art.page(id,'idle','ally')
		art.page(id,'walk','ally')

func advance(dt: float, direction: Vector2):
	clock += dt
	ritual = maxf(0.,ritual-dt)
	moving = direction != Vector2.ZERO
	if moving:
		actor += direction.normalized()*240.*dt
		actor = actor.clamp(Vector2(110,350),Vector2(LENGTH-130,495))
		facing = Art.bearing_for(direction)
		walking += dt
	camera_x = lerpf(camera_x,clampf(actor.x-490.,0.,LENGTH-960.),1.-exp(-dt*7.))
	queue_redraw()

func point_at(id: String) -> Vector2:
	return STOPS[id] - Vector2(roundf(camera_x),0)

func sprite(id: String, position: Vector2, action: String, size_factor: float, shift: float = 0.):
	var clip = Art.clip(id,action,facing)
	var ms = (walking if action=='walk' else clock)*1000.+shift
	var index = clip.frame_at(fposmod(ms,clip.duration_ms))
	var rect = clip.regions[index]
	var foot = position.round()
	draw_rect(Rect2(foot-Vector2(12,2),Vector2(24,4)),Color('#11151c77'))
	draw_texture_rect_region(art.page(id,action,'ally'),Rect2((foot-clip.anchors[index]*size_factor).round(),rect.size*size_factor),rect)

func _draw():
	var cam = roundf(camera_x)
	var sky = Color('#343447').lerp(tint,.35)
	draw_rect(Rect2(0,0,960,540),sky)
	draw_rect(Rect2(0,148,960,392),tint.darkened(.42))
	# Three bands use different camera speeds; all positions stay on pixel boundaries.
	for band in 3:
		var shade = sky.lerp(tint.darkened(.59),.28+band*.24)
		var offset = fposmod(cam*(.11+band*.18),240.)
		for i in range(-1,6):
			var x = roundf(i*240-offset)
			var y = 157.+band*36.
			draw_colored_polygon(PackedVector2Array([Vector2(x,y+78),Vector2(x+55,y+22),Vector2(x+99,y),Vector2(x+165,y+44),Vector2(x+240,y+61),Vector2(x+240,y+126),Vector2(x,y+126)]),shade)
	var first = floori(cam/256.)
	for i in range(first,first+5):
		draw_texture_rect(GRASS,Rect2(i*256-cam,253,256,287),false,tint.lerp(Color.WHITE,.30))
	var left = Vector2(-100,ROAD_Y)
	draw_line(left,Vector2(1060,ROAD_Y+26),Color('#382f2c'),106.)
	draw_line(left,Vector2(1060,ROAD_Y+26),tint.lerp(Color('#a18360'),.64),91.)
	for i in range(floori(cam/41.),floori(cam/41.)+26):
		draw_rect(Rect2(i*41-cam,376+((i*37)%59),6+i%5,2),Color('#dac6a36a'))
	if land in ['north','east']:
		draw_rect(Rect2(0,257,960,26),Color('#547e8f').lerp(tint,.2))
		for i in 28:
			draw_rect(Rect2(roundf(fposmod(i*43-cam*.8,980)),261+(i*19)%18,14,1),Color('#b3d4d366'))
	for point in trees:
		if point.y > 485.:break
		if absf(point.x-cam-480.)<585.:
			draw_texture_rect(TREE if land=='west' else FOREST,Rect2(point-Vector2(cam+47,104),Vector2(94,106)),false,tint.lerp(Color.WHITE,.68))
	for id in STOPS:
		var point = point_at(id)
		if point.x < -140. or point.x > 1100.:continue
		match id:
			'village':
				draw_texture_rect(CAMP,Rect2(point-Vector2(102,136),Vector2(130,130)),false)
				sprite('U01',point+Vector2(23,-18),'idle',1.)
			'shop':
				draw_texture_rect(STORE,Rect2(point-Vector2(96,165),Vector2(190,190)),false)
			'camp':
				draw_texture_rect(CAMP,Rect2(point-Vector2(84,146),Vector2(160,160)),false)
				fire(point+Vector2(51,-15),false)
			'altar':
				draw_texture_rect(ALTAR,Rect2(point-Vector2(94,151),Vector2(188,188)),false,tint.lerp(Color.WHITE,.65))
				sprite('U01',point+Vector2(37,-12),'idle',1.)
				fire(point-Vector2(30,20),ritual>0.)
				if ritual>0.:
					for i in 12:
						var angle = i*TAU/12.
						var q = (point+Vector2(cos(angle)*58.,sin(angle)*18.)-Vector2(0,20.+fposmod(clock*22.+i*9,34.))).round()
						draw_rect(Rect2(q,Vector2(4,4)),Color('#ffdc8b'))
			'warning','fork':
				draw_rect(Rect2(point-Vector2(3,39),Vector2(6,38)),Color('#4a3126'))
				draw_rect(Rect2(point-Vector2(27,45),Vector2(54,18)),Color('#ba9266'))
		var active = shown_markers.get(id,true)
		draw_circle(point-Vector2(0,89),5.,Color('#ffe49c') if active else Color('#a0a7a1'))
	var action = 'walk' if moving else 'idle'
	var screen_actor = actor-Vector2(cam,0)
	var direction = Vector2(-1 if facing in [5,6,7] else 1,0)
	for index in 3:
		var foot = screen_actor-direction*(63.+index*34.)+Vector2(0,23.+index*14.)
		sprite(['U02','U05','U10'][index],foot,action,1.35,index*128.)
	var cart = (screen_actor-direction*194.+Vector2(0,54)).round()
	draw_rect(Rect2(cart-Vector2(22,17),Vector2(44,21)),Color('#694b32'))
	draw_rect(Rect2(cart-Vector2(18,22),Vector2(34,8)),Color('#b49b6e'))
	draw_circle(cart+Vector2(-13,6),8.,Color('#332824'))
	draw_circle(cart+Vector2(13,6),8.,Color('#332824'))
	sprite('U20',screen_actor,action,1.6)
	for point in trees:
		if point.y <= 485.:continue
		var x = point.x-cam*1.08
		if x > -100. and x < 1040.:
			draw_texture_rect(FOREST,Rect2(x-51,point.y-114,102,115),false,tint.lerp(Color.WHITE,.62))
	if weather:
		for i in 9:
			var x = roundf(fposmod(i*183.+clock*9.-cam*.43,1160.)-100.)
			draw_rect(Rect2(x,266+i%3*36,106+i*5,3),Color('#d5d1e315'))
	draw_rect(Rect2(0,0,960,41),Color('#11141d'))
	draw_rect(Rect2(0,500,960,40),Color('#11141d'))

func fire(point: Vector2, bright: bool):
	draw_rect(Rect2(point-Vector2(22,6),Vector2(44,9)),Color('#261f26'))
	for i in 5:
		var h = floorf(4.+absf(sin(clock*12.+i))*12.)*(1.65 if bright else 1.)
		draw_rect(Rect2(point.x-12+i*5,point.y-h,5,h),Color('#ffd279') if i%2==0 else Color('#d56c40'))
