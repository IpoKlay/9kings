extends Node2D
## The square is open ground. All tall scenery stays outside its playable bounds.
var trial
var landscape_rect=Rect2(-300,-240,2700,2085)
const GRASS=preload('res://assets/environments/iberia-rts.png')
const SOIL=preload('res://assets/environments/iberia.png')
const OAK=preload('res://assets/environments/oak.png')
const MEDIC=preload('res://assets/facilities/medic_2.png')
const SIEGE=preload('res://assets/facilities/siege_1.png')
const Scenery=preload('res://scripts/battle_environment.gd')
var environment=Scenery.new()
const BANK=[Vector2(8,50),Vector2(29,26),Vector2(61,17),Vector2(88,25),
	Vector2(107,52),Vector2(147,55),Vector2(179,36),Vector2(205,18),Vector2(232,14),
	Vector2(271,31),Vector2(294,37),Vector2(280,59),Vector2(248,70),Vector2(225,90),
	Vector2(185,99),Vector2(156,103),Vector2(128,101),Vector2(94,89),Vector2(60,85),Vector2(29,72),Vector2(15,69)]
# Projected scenery coordinates; these footprints never occupy the walkable square.
const TREES=[Vector3(-440,110,214),Vector3(-230,165,190),Vector3(-98,220,140),
	Vector3(-365,350,196),Vector3(-175,360,184),Vector3(-94,420,146),Vector3(-255,510,180),
	Vector3(-600,310,220),Vector3(-540,560,202),Vector3(-390,610,184),
	Vector3(130,-25,170),Vector3(270,-65,190),Vector3(415,-30,152),
	Vector3(2220,95,182),Vector3(2380,160,204),Vector3(2260,330,190),
	Vector3(2188,390,154),Vector3(2420,470,210),Vector3(2300,550,176),
	Vector3(2630,235,224),Vector3(2585,510,202),Vector3(2765,660,230),
	Vector3(1770,-30,180),Vector3(1920,-55,168),
	Vector3(-460,1400,202),Vector3(-230,1480,186),Vector3(-95,1550,148),
	Vector3(-360,1650,210),Vector3(-215,1730,174),Vector3(-555,1720,220),
	Vector3(120,1790,174),Vector3(290,1780,164),Vector3(425,1820,190),
	Vector3(2230,1320,186),Vector3(2390,1410,204),Vector3(2200,1510,166),
	Vector3(2335,1640,190),Vector3(2550,1650,216),Vector3(2690,1530,202),
	Vector3(1770,1800,178),Vector3(1910,1780,170),Vector3(2070,1830,190)]

func advance(delta: float):
	environment.tick(delta)
	queue_redraw()

func _draw():
	var r=trial.rules
	if not r.square_battle:return
	var map: Rect2=r.projection*r.bounds
	draw_meadow(map)
	draw_road(map)
	draw_ground_details(map)
	draw_borders(map)
	draw_camps(map)
	for i in TREES.size():draw_tree(TREES[i],i)
	# The boundary is a quiet ground edge; only deployment has the two zone guides.
	draw_rect(map,Color('#c0b88b66'),false,2)
	if r.phase=='deploy':draw_deployment(r)

func draw_meadow(map: Rect2):
	# Mirrored large crops meet on identical source pixels; source texels stay near 1:1.
	# Backdrop exceeds the camera clamp so Tab overview never exposes the clear colour.
	for row in range(-1,3):
		for col in range(-1,3):
			var rect=Rect2(Vector2(col*1280,row*960),Vector2(1280,960))
			var corners=PackedVector2Array([rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)])
			var uv=PackedVector2Array()
			for corner in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
				if posmod(col,2):corner.x=1-corner.x
				if posmod(row,2):corner.y=1-corner.y
				uv.append((Vector2(420,400)+corner*Vector2(1280,960))/GRASS.get_size())
			draw_polygon(corners,PackedColorArray([Color.WHITE]),uv,GRASS)
	draw_rect(Rect2(-1280,-960,5120,3840),Color('#25392366'))
	draw_rect(map,Color('#8b95616b'))

func soil_patch(points: PackedVector2Array,opacity: float):
	var uv=PackedVector2Array()
	var rect=Rect2(points[0],Vector2.ZERO)
	for p in points:rect=rect.expand(p)
	for p in points:
		uv.append((Vector2(520,280)+(p-rect.position)/rect.size*Vector2(740,480))/SOIL.get_size())
	draw_polygon(points,PackedColorArray([Color(1,1,1,opacity)]),uv,SOIL)

func draw_road(map: Rect2):
	# Worn grass, not a wall or trench: both flanks retain their full movement space.
	var centers=[Vector2(1010,-240),Vector2(1040,50),Vector2(1010,300),Vector2(1110,565),
		Vector2(1100,825),Vector2(1000,1110),Vector2(1060,1360),Vector2(1110,1630),Vector2(1090,1845)]
	var widths=[95.,105.,90.,120.,140.,115.,120.,105.,100.]
	for layer in [1.0,.67]:
		var points=PackedVector2Array()
		for i in centers.size():points.append(centers[i]-Vector2(widths[i]*layer,0))
		for i in range(centers.size()-1,-1,-1):points.append(centers[i]+Vector2(widths[i]*layer,0))
		soil_patch(points,.20 if layer==1.0 else .16)
	soil_patch(PackedVector2Array([Vector2(540,910),Vector2(680,845),Vector2(930,850),
		Vector2(1100,925),Vector2(1060,1010),Vector2(800,1035),Vector2(610,1000)]),.13)
	soil_patch(PackedVector2Array([Vector2(1120,1260),Vector2(1330,1245),Vector2(1500,1310),
		Vector2(1435,1400),Vector2(1220,1390),Vector2(1115,1340)]),.14)
	# Small paired wheel ruts lead into each rear camp, never across the fighting line.
	for y in range(70,330,22):
		for x in [1020,1050]:draw_line(Vector2(x,y),Vector2(x+2,y+12),Color('#6c674644'),2)
	for y in range(int(map.end.y)-260,int(map.end.y),22):
		for x in [1064,1094]:draw_line(Vector2(x,y),Vector2(x+2,y+12),Color('#6c674644'),2)

func draw_ground_details(map: Rect2):
	# Sparse flat stones / worn grass; no decorative object implies an internal obstacle.
	for i in 64:
		var p=Vector2(48+posmod(i*397,2000),42+posmod(i*269,1490))
		if not map.has_point(p):continue
		var color=Color('#84906a77') if i%3 else Color('#ada37966')
		draw_rect(Rect2(p,Vector2(4+i%3,2)),color)
		if i%4==0:draw_rect(Rect2(p+Vector2(7,3),Vector2(3,2)),Color('#4d5f4280'))

func draw_bank(pos: Vector2,size: Vector2):
	var vertices=PackedVector2Array()
	var uv=PackedVector2Array()
	for p in BANK:
		vertices.append((pos+p/Vector2(302,110)*size).round())
		uv.append((Vector2(1950,245)+p)/GRASS.get_size())
	draw_polygon(vertices,PackedColorArray([Color.WHITE]),uv,GRASS)

func draw_borders(map: Rect2):
	for row in [[-280.,350.,250.,108.],[-260.,435.,238.,85.],[-290.,1480.,260.,110.],
		[2120.,355.,250.,100.],[2215.,465.,240.,85.],[2120.,1435.,270.,105.],
		[40.,-115.,320.,100.],[300.,-93.,270.,85.],[1660.,-112.,330.,105.],
		[105.,1635.,320.,100.],[335.,1680.,245.,90.],[1710.,1630.,310.,110.]]:
		draw_bank(Vector2(row[0],row[1]),Vector2(row[2],row[3]))
	# Low boundary stones give an exact edge without closing the visual camp entrances.
	for x in range(50,int(map.end.x),140):
		if x>850 and x<1240:continue
		for y in [-5.,map.end.y+5]:
			draw_rect(Rect2(Vector2(x,y),Vector2(9,4)),Color('#817f62'))
			draw_rect(Rect2(Vector2(x+1,y),Vector2(6,2)),Color('#b7b28c'))

func draw_camps(map: Rect2):
	for north in [true,false]:
		var y=-22. if north else map.end.y+151.
		var tint=Color('#b8c1b1') if north else Color.WHITE
		for row in [[MEDIC,Vector2(760,y),Vector2(146,146)],[SIEGE,Vector2(1390,y+3),Vector2(150,150)]]:
			var p: Vector2=row[1]
			var size: Vector2=row[2]
			draw_texture_rect(row[0],Rect2(p-Vector2(size.x*.5,size.y),size),false,tint)
		for x in [965.,1170.]:
			var root=Vector2(x,-12 if north else map.end.y+91)
			environment.draw_flag(self,root,int(x),north)

func draw_tree(tree: Vector3,index: int):
	var root=Vector2(tree.x,tree.y)
	var size=Vector2.ONE*tree.z
	for strip in 16:
		var f=strip/16.0
		var sway=environment.tree_sway(1,index%environment.wind_profiles[0].size(),f,environment.clock)
		var src=Rect2(0,OAK.get_height()*f,OAK.get_width(),OAK.get_height()/16.0)
		var dst=Rect2(root-Vector2(size.x*.5,size.y)+Vector2(sway,size.y*f),Vector2(size.x,size.y/16.0+.5))
		draw_texture_rect_region(OAK,dst,src)

func draw_deployment(r):
	for y in [r.SIZE/3,r.SIZE*2/3]:
		var a: Vector2=r.projection*Vector2(0,y)
		var b: Vector2=r.projection*Vector2(r.SIZE,y)
		draw_dashed_line(a,b,Color('#d2c79899'),2,20)
	var font=trial.hint.get_theme_font('font')
	for row in [[105.,trial.words('敌军部署区','ENEMY DEPLOYMENT')],
		[1045.,trial.words('交战区 · 不可部署','BATTLEFIELD · NO DEPLOYMENT')],
		[1920. if trial.zoom<.75 else 2040.,trial.words('我军部署区','YOUR DEPLOYMENT')]]:
		var font_size=roundi(24.0/trial.zoom)
		var width=font.get_string_size(row[1],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		var p: Vector2=r.projection*Vector2((r.SIZE-width)/2,row[0])
		var screen: Vector2=(p-trial.camera_offset)*trial.zoom
		if screen.y<120 or screen.y>900:continue
		draw_string(font,p+Vector2(2,2),row[1],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color('#263727'))
		draw_string(font,p,row[1],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color('#dbcfaa'))
