extends SceneTree
## Bake the approved coat lighting after pack_approved_animations.py.
## Run with Godot --headless --path godot-game --script res://tools/paint_cavalry_lighting.gd.
const BASE='res://assets/strategy/unit-animations/'
const BROWN_RAMP=['4d302b','623b30','784733','925538','ad6945','c38355','d49864']
const GREY_RAMP=['282b2d','3a4248','505a60','626e72','758184','909b97','a6ada4']
const BROWN={0x442a24:0,0x4b2d23:1,0x543327:1,0x552d23:1,0x5c3528:1,0x64392a:1,0x6b3c2a:1,
	0x76422d:2,0x824c32:2,0x8e5233:3,0x9a5b3a:4,0xa5623d:4,0xb16c43:5,0xc17c4e:6,
	0x7b4933:2,0x834d36:2,0x8c5439:2,0x92563a:3,0x9b5d3c:3,0xab6a45:4,0xa46542:4,0x9c6341:4,
	0x7c4a34:2,0x834e36:2,0x8c5339:3,0x94593c:3,0x9b5f3f:4,0xa46643:4,0x734431:2,
	0x734433:2,0x7e4b36:2,0x89543b:2,0x945a3e:3,0x9b6142:4,0xa46543:4,
	0x734330:2,0x804c33:2,0x8b5338:3,0x93583a:3,0x9b5e3d:4}
const GREY={0x2b2726:0,0x332f2e:1,0x3e3b38:1,0x484746:2,0x555857:3,0x656967:3,0x828581:5}
const ACTIONS=['idle','walk','attack','hurt','charge']

func _initialize():
	var roster: Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://data/generated/approved_unit_animations.json'))
	for tier in range(18,24):
		var unit='U%02d'%tier
		for action in ACTIONS:
			for suffix in (['','-enemy'] if unit in ['U18','U23'] else ['']):
				var name: String=unit+'/'+action+suffix+'.png'
				var path=ProjectSettings.globalize_path(BASE+name)
				var source=Image.load_from_file(path)
				if source==null:
					push_error('Cannot read '+name)
					quit(1)
					return
				var revised: Image=source.duplicate()
				var touched={}
				for bearing in 8:
					for frame in roster[unit][action][bearing].frames:
						paint_frame(source,revised,frame,bearing,unit=='U23',touched)
				if touched.is_empty():continue
				if revised.save_png(path)!=OK:
					push_error('Cannot save '+name)
					quit(1)
					return
				print(name,': ',touched.size(),' coat pixels')
	quit(0)

func plane(point: Vector2,center: Vector2,radius: Vector2,side: float) -> float:
	var q=(point-center)/radius
	var square=q.length_squared()
	if square>1.:return -2.
	# Round barrel and shoulder under a top-left key. Steps are quantized to the coat ramp.
	return -.48*q.x*side-.66*q.y+.47*sqrt(1.-square)

func coat_grade(p: Vector2,bearing: int,grey: bool) -> int:
	var side=1. if bearing in [1,2,3] else -1.
	var local=Vector2(p.x*side,p.y)
	var light: float
	if bearing in [2,6]:
		var rump=plane(local,Vector2(-19,-25 if grey else -27),Vector2(12,12),side)
		var chest=plane(local,Vector2(11,-26),Vector2(8,13),side)
		var neck=plane(local,Vector2(16,-36 if grey else -39),Vector2(9,10),side)
		light=maxf(rump,maxf(chest,neck))
	elif bearing in [1,3,5,7]:
		var aft=bearing in [3,5]
		var rump=plane(local,Vector2(-12,-25),Vector2(12,13),side)
		var chest=plane(local,Vector2(7,-25),Vector2(9,12),side)
		var neck=plane(local,Vector2(10,-36 if not aft else -41),Vector2(9,11),side)
		light=maxf(rump,maxf(chest,neck))
	else:
		light=plane(p,Vector2(0,-27),Vector2(11,16),1.)
	if light>.71:return 2
	if light>.41:return 1
	if light>=.12:return 0
	return -1 if light>=-1. else 0

func paint_frame(source: Image,dest: Image,f: Array,bearing: int,grey: bool,touched: Dictionary):
	var material=GREY if grey else BROWN
	var ramp=GREY_RAMP if grey else BROWN_RAMP
	for y in range(f[3]):
		for x in range(f[2]):
			var pos=Vector2i(f[0]+x,f[1]+y)
			if touched.has(pos):continue
			var color=source.get_pixelv(pos)
			if color.a!=1.:continue
			var p=Vector2(x-f[4],y-f[5])
			var lateral=absf(p.x)
			# Exclude rider and center of the saddle. Above the withers only the exposed neck is painted.
			var neck_side=1. if bearing in [1,2,3] else -1.
			if p.y<(-45 if grey else -49):continue
			if p.y< -34. and (bearing in [0,4] or p.x*neck_side<7.):continue
			if p.y< -19. and lateral<6. and bearing not in [0,4]:continue
			var rgb=color.to_rgba32()>>8
			var level: int=material.get(rgb,-1)
			if level<2:continue
			var grade=coat_grade(p,bearing,grey)
			if p.y> -16.:
				# Separate lower and far legs from the barrel while retaining bridle and hoof pixels.
				grade=-1 if p.x>1. else 0
			if grade==0:continue
			# Preserve the original darker seams and reserve the top two tones for broad lit coat.
			var value=clampi(level+grade,1,5)
			var new=Color(ramp[value])
			if new==color:continue
			dest.set_pixelv(pos,new)
			touched[pos]=true
