extends SceneTree
## Scoped native sprite builder: only the cavalry sheets, never terrain or other units.
var rider: Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://data/sources/cavalry_rider.json'))
var ink=Color('#2b2926')
var coat=Color('#806044')
var lit=Color('#ac8559')
var shade=Color('#574639')
var gold=Color('#c3a15a')
var image: Image

func _initialize():
	for side in ['ally','enemy']:
		for mode in ['idle','walk','attack','testudo','testudo_walk','testudo_attack']:
			var sheet=Image.create(1024,64,false,Image.FORMAT_RGBA8)
			for frame in 16:
				image=Image.create(64,64,false,Image.FORMAT_RGBA8)
				draw_horse(frame,mode,side=='enemy')
				sheet.blit_rect(image,Rect2i(0,0,64,64),Vector2i(frame*64,0))
			assert(sheet.save_png('res://assets/unit_cavalry_'+side+'_'+mode+'.png')==OK)
	print('CAVALRY: rebuilt 12 native sheets, 16 frames each')
	quit()

func dot(x: int,y: int,c: Color):
	if x>=0 and y>=0 and x<64 and y<64:image.set_pixel(x,y,c)

func rect(x: int,y: int,w: int,h: int,c: Color):
	for yy in range(y,y+h):
		for xx in range(x,x+w):dot(xx,yy,c)

func line(a: Vector2,b: Vector2,c: Color,width: int=1):
	var steps=maxi(1,ceili(maxf(absf(b.x-a.x),absf(b.y-a.y))))
	for i in steps+1:
		var p=a.lerp(b,float(i)/steps).round()
		rect(int(p.x),int(p.y),width,width,c)

func poly(points: Array,c: Color):
	var vertices=PackedVector2Array()
	for p in points:vertices.append(Vector2(p[0],p[1]))
	for y in 64:
		for x in 64:
			if Geometry2D.is_point_in_polygon(Vector2(x+.5,y+.5),vertices):dot(x,y,c)

func part(name: String,offset: Vector2i,enemy: bool):
	var colors=rider.palette.duplicate()
	if enemy:
		colors.r='#536871';colors.L='#98a6a3';colors.R='#283b48'
	for p in rider.parts:
		if p.name!=name:continue
		for y in p.op.rows.size():
			var row: String=p.op.rows[y]
			for x in row.length():
				if row[x]!='.':dot(p.op.x+x+offset.x,p.op.y+y+offset.y,Color(colors[row[x]]))

func draw_horse(frame: int,mode: String,enemy: bool):
	var moving=mode.contains('walk')
	var attacking=mode.contains('attack')
	var phase=frame*TAU/16
	var bob=roundi(sin(phase*2)) if moving else 0
	var surge=roundi(sin(frame*PI/15)*2) if attacking else 0
	var red=Color('#536871') if enemy else Color('#872e2a')
	# Four offset legs have knees, fetlocks and hooves; far legs remain in shadow.
	for j in 4:
		var front=j%2==1
		var near=j>=2
		var root=Vector2((40 if front else 17)+(3 if near else 0),41+bob)
		var cycle=phase+(0 if j==0 else PI if j==1 else PI*.65 if j==2 else PI*1.65)
		var swing=sin(cycle)*6 if moving else (float(surge)*(-1 if front else 1))
		var lift=maxf(0,cos(cycle))*4 if moving else 0
		var knee=root+Vector2(swing*.4+(-1 if front else 2),7)
		var hoof=root+Vector2(swing,15-lift-bob)
		line(root,knee,ink,3);line(knee,hoof,ink,2)
		line(root+Vector2(1,0),knee,coat if near else shade,2)
		line(knee+Vector2(1,0),hoof,lit if near else shade)
		rect(int(hoof.x)-1,int(hoof.y),4,2,ink)
	# Compact rounded barrel, pronounced shoulder and rump instead of a rectangular plank.
	poly([[10,36+bob],[13,32+bob],[23,30+bob],[35,30+bob],[44,33+bob],[47,40+bob],[41,46+bob],[18,46+bob],[11,42+bob]],ink)
	poly([[12,36+bob],[16,33+bob],[24,32+bob],[36,32+bob],[43,34+bob],[44,40+bob],[40,44+bob],[19,44+bob],[13,41+bob]],coat)
	poly([[14,35+bob],[23,33+bob],[34,33+bob],[40,35+bob],[35,38+bob],[20,38+bob],[14,40+bob]],lit)
	poly([[14,40+bob],[25,41+bob],[39,39+bob],[43,40+bob],[39,44+bob],[20,44+bob]],shade)
	# Mane, arched neck, separate ears, long muzzle and bridle at the visible three-quarter cheek.
	poly([[36,34+bob],[40,24+bob],[45,20+bob],[50,20+bob],[53,25+bob],[60,29+bob],[59,34+bob],[53,35+bob],[49,31+bob],[47,40+bob],[42,44+bob]],ink)
	poly([[40,33+bob],[43,25+bob],[46,23+bob],[50,23+bob],[51,27+bob],[58,30+bob],[57,33+bob],[53,33+bob],[48,28+bob],[46,38+bob],[43,41+bob]],coat)
	poly([[43,27+bob],[46,24+bob],[49,24+bob],[49,27+bob],[46,29+bob],[44,36+bob],[42,37+bob]],lit)
	poly([[45,21+bob],[44,17+bob],[47,19+bob],[48,22+bob]],ink)
	poly([[49,22+bob],[50,18+bob],[52,23+bob]],shade)
	for y in range(24,35,3):rect(39+(35-y)/3,y+bob,3,2,ink)
	dot(50,26+bob,ink);dot(49,25+bob,Color('#d7bd89'))
	line(Vector2(51,28+bob),Vector2(55,33+bob),Color('#c6af7b'))
	line(Vector2(53,32+bob),Vector2(36,31+bob),ink)
	# Tail and saddle cloth.
	var tail=roundi(sin(phase)*2) if moving else 0
	poly([[12,34+bob],[9,34+bob],[6,40+bob],[5+tail,47+bob],[8+tail,45+bob],[11,39+bob]],ink)
	poly([[21,30+bob],[36,30+bob],[37,41+bob],[29,43+bob],[21,40+bob]],ink)
	poly([[22,31+bob],[35,31+bob],[35,40+bob],[29,41+bob],[22,39+bob]],red)
	line(Vector2(23,38+bob),Vector2(34,39+bob),gold)
	rect(24,29+bob,11,3,shade)
	# Retain the approved soldier's helmet and armour; bent riding leg replaces standing legs.
	part('Body',Vector2i(15+surge,11+bob),enemy)
	part('Helmet',Vector2i(15+surge,11+bob),enemy)
	poly([[29+surge,29+bob],[33+surge,31+bob],[31,37+bob],[34,39+bob],[34,41+bob],[29,40+bob],[28,35+bob]],ink)
	line(Vector2(30+surge,31+bob),Vector2(29,36+bob),Color('#a97456'),2)
	line(Vector2(30,37+bob),Vector2(33,39+bob),shade,2)
	# Shield and thrust are readable while keeping the cavalry identity.
	part('Shield',Vector2i(12+surge,13+bob),enemy)
	var tip=Vector2(59,18+bob+(-3 if attacking and frame<8 else 0))
	line(Vector2(35+surge,29+bob),tip,ink,2)
	line(Vector2(35+surge,29+bob),tip,Color('#a47c50'))
	poly([[tip.x-4,tip.y],[tip.x+3,tip.y-3],[tip.x+1,tip.y+2]],Color('#c8cec2'))
