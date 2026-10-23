extends Node2D
## The same isometric projection as the web edition; UI hit tests use its inverse.
var game
var preview: Array = []
var textures = {}
var hover_cell = -1
var selected_cell = -1
var clock = 0.0
var attack_times = {}
var death_times = {}
var particles: Array = []
var stains: Array = []
var captions: Array = []
var shake = 0.0
var impact = true
var language = 'zh'
var translated = {}
var world_font = SystemFont.new()

func _ready():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world_font.font_names = PackedStringArray(['Songti SC','Noto Serif CJK SC','serif'])
func tex(id: String):
	if not textures.has(id): textures[id] = load('res://assets/'+id+'.png')
	return textures[id]
func text(s: String) -> String:
	return translated.get(s,s) if language=='zh' else s
func project(x: float,y: float,z: float = 0) -> Vector2:
	return Vector2(940+.76*(x-800)-.68*(y-450),510+.27*(x-800)+.40*(y-450)-z)
func unproject(p: Vector2) -> Vector2:
	var v = p-Vector2(940,510)
	var det = .76*.40+.68*.27
	return Vector2(800+(.40*v.x+.68*v.y)/det,450+(-.27*v.x+.76*v.y)/det)
func center(cell: int) -> Vector2:
	return Vector2(132+cell%4*120,321+int(cell/4.0)*126)
func cell_at(p: Vector2) -> int:
	var w = unproject(p)
	var col = int(floor((w.x-72)/120))
	var row = int(floor((w.y-258)/126))
	return row*4+col if col>=0 and col<4 and row>=0 and row<3 else -1
func cell_shape(cell: int) -> PackedVector2Array:
	var p = center(cell)
	return PackedVector2Array([project(p.x-57,p.y-60),project(p.x+57,p.y-60),project(p.x+57,p.y+60),project(p.x-57,p.y+60)])
func refresh():
	preview = game.muster()
	queue_redraw()
func clear_battle():
	attack_times.clear()
	death_times.clear()
	particles.clear()
	stains.clear()
	captions.clear()
	shake = 0
func tick(delta):
	clock += delta
	shake = maxf(0,shake-delta*16)
	for p in particles:
		p.life -= delta
		p.pos += p.velocity*delta
		p.velocity.y += delta*100
	particles = particles.filter(func(p):return p.life>0)
	for c in captions:
		c.life -= delta
		c.pos.y -= delta*18
	captions = captions.filter(func(c):return c.life>0)
	queue_redraw()
func burst(p: Vector2,color: Color,count: int):
	for i in count:
		if particles.size()>=180: particles.pop_front()
		particles.append({'pos':p,'velocity':Vector2(randf_range(-100,100),randf_range(-100,20)),'life':randf_range(.18,.5),'color':color,'size':randf_range(2,5)})
func events(items: Array):
	for e in items:
		var p = project(595+e.x*.91,475+e.y*.9,14)
		match e.kind:
			'attack': attack_times[e.id] = clock
			'hit':
				burst(p,Color('#e1cf94') if e.absorbed>0 else Color('#9f3e35'),3 if e.absorbed>0 else 2)
				if e.get('broken',false):
					captions.append({'pos':p-Vector2(20,30),'life':.75,'text':'SHIELD BROKEN','color':Color('#e6d9a6')})
				if e.damage>0 and stains.size()<240:
					stains.append({'pos':p+Vector2(randf_range(-14,14),15),'size':Vector2(randf_range(3,10),randf_range(2,4))})
			'blast':
				burst(p,Color('#c6af76'),16)
				if impact: shake = 3
			'death':
				death_times[e.id] = clock
				burst(p,Color('#a04234'),8)
				captions.append({'pos':p-Vector2(20,35),'life':.85,'text':'ROUTED' if e.side=='enemy' else 'SQUAD LOST','color':Color('#ecd08b') if e.side=='enemy' else Color('#d28979')})
				if impact: shake = 2
			'breach':
				if impact: shake = 5

func _draw():
	if game == null: return
	var offset = Vector2(randf_range(-shake,shake),randf_range(-shake,shake)) if shake>0 else Vector2.ZERO
	draw_set_transform(offset)
	draw_texture_rect(tex('terrain'),Rect2(0,0,1920,1080),false)
	for s in stains: draw_rect(Rect2(s.pos,s.size),Color('#602b29'))
	var queue: Array = []
	for i in game.rules.woodland.size():
		var tree = game.rules.woodland[i]
		queue.append({'kind':'tree','pos':Vector2(tree[0],tree[1]),'index':i})
	for i in 3:
		queue.append({'kind':'life','pos':project(-25,380+i*66),'live':i<game.g.defense})
	for i in 12:
		var b = game.building_at(i)
		var wc = center(i)
		var p = project(wc.x,wc.y)
		if game.g.battle == null:
			var valid = game.g.phase=='place' and (b==null or (b.type==game.g.pending and b.level<3))
			var active = i==hover_cell or i==selected_cell
			if valid or active:
				var polygon = cell_shape(i)
				draw_colored_polygon(polygon,Color(0.88,.83,.59,.17 if active else .08))
				polygon.append(polygon[0])
				draw_polyline(polygon,Color('#f0dca0') if active else Color('#96ab79'),2)
				if b==null and valid:
					draw_line(p-Vector2(5,0),p+Vector2(5,0),Color('#c6d1a5'),2)
					draw_line(p-Vector2(0,5),p+Vector2(0,5),Color('#c6d1a5'),2)
		if b!=null: queue.append({'kind':'building','pos':p,'building':b,'cell':i})
	var units = preview if game.g.battle==null else game.g.battle.units
	for u in units:
		var dead = u.hp<=0
		var age = clock-death_times.get(u.id,clock) if dead else 0
		var p = project(595+u.x*.91,475+u.y*.9)
		if u.type=='siege':
			queue.append({'kind':'siege','pos':p,'unit':u,'dead':dead})
			continue
		for i in 9:
			if u.type=='medic' and i%3!=0: continue
			if u.type=='cavalry' and i%2!=0: continue
			var dir = 1 if u.side=='ally' else -1
			var compact = .72 if u.get('testudo',false) else 1.0
			var x = 595+u.x*.91+(20-(i%3)*22)*dir*compact
			var y = 475+u.y*.9+(-25+int(i/3.0)*25)*compact
			queue.append({'kind':'soldier','pos':project(x,y),'unit':u,'index':i,'dead':dead,'age':age})
	queue.sort_custom(func(a,b):return a.pos.y<b.pos.y)
	for item in queue:
		var p = item.pos
		match item.kind:
			'tree': draw_texture(tex('tree_'+str(item.index)),p-Vector2(80,170))
			'life': draw_texture(tex('life_'+str(int(item.live))),p-Vector2(48,70))
			'building':
				var b = item.building
				var lift = 4 if item.cell==selected_cell and game.g.battle==null else 0
				draw_texture_rect(tex('building_'+b.type+'_'+str(int(b.level))),Rect2(p-Vector2(37.1,63.7+lift),Vector2(74.2,74.2)),false)
				if game.g.battle==null: draw_string(world_font,p+Vector2(-24,16),['','I','II','III'][int(b.level)],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color('#e0d4aa'))
			'siege':
				var frame = clampi(int((clock-attack_times.get(item.unit.id,-10.0))/.75*16),0,15)
				var color = Color(.45,.38,.34,.7) if item.dead else (Color(.7,.85,1) if item.unit.side=='enemy' else Color.WHITE)
				draw_texture_rect_region(tex('catapult'),Rect2(p-Vector2(40,65),Vector2(73,73)),Rect2(frame*80,0,80,80),color)
			'soldier':
				var u = item.unit
				var attack_age = clock-attack_times.get(u.id,-10.0)-(item.index%3)*.032-int(item.index/3.0)*.018
				var mode = 'idle'
				var frame = 0
				if not item.dead:
					if attack_age>=0 and attack_age<.48:
						mode = 'attack'
						frame = clampi(int(attack_age/.48*16),0,15)
					elif u.moving and game.g.phase=='battle':
						mode = 'walk'
						frame = int((clock*13+item.index*.83+u.id*.52)/TAU*16)%16
				if u.get('testudo',false) and item.index%3>0: mode = 'testudo' if mode=='idle' else 'testudo_'+mode
				var dir = 1.0 if u.side=='ally' else -1.0
				var angle = -dir*minf(1,item.age/.3)*1.5 if item.dead else 0.0
				draw_set_transform(p+offset,angle,Vector2(dir,1))
				var color = Color(.55,.4,.38,.8) if item.dead else Color.WHITE
				if not item.dead and u.flash>0: color = Color(1.5,1.4,1.2)
				draw_texture_rect_region(tex('unit_'+u.type+'_'+u.side+'_'+mode),Rect2(-32,-52,64,64),Rect2(frame*64,0,64,64),color)
				if not item.dead and u.hp<u.maxHp*.65: draw_rect(Rect2(-1,-13,2,4),Color('#8d292d'))
				draw_set_transform(offset)
	if game.g.battle!=null:
		for u in units:
			if u.hp<=0: continue
			var p = project(595+u.x*.91,475+u.y*.9)
			draw_rect(Rect2(p-Vector2(22,37),Vector2(44,5)),Color('#183626'))
			draw_rect(Rect2(p-Vector2(21,36),Vector2(42*u.hp/u.maxHp,3)),Color('#e6c980') if u.side=='ally' else Color('#acc5c9'))
			if u.shield>0: draw_rect(Rect2(p-Vector2(21,41),Vector2(42*u.shield/u.maxShield,2)),Color('#c9eddb'))
			if u.get('healUntil',0)>game.g.battle.time:
				draw_line(p-Vector2(4,50),p+Vector2(4,-50),Color('#a2ddba'),3)
				draw_line(p-Vector2(0,54),p-Vector2(0,46),Color('#a2ddba'),3)
			if u.get('burnUntil',0)>game.g.battle.time:
				draw_rect(Rect2(p+Vector2(22,-23),Vector2(4,10)),Color('#d4813c'))
		for shot in game.g.battle.projectiles:
			var t = 1-shot.life/shot.duration
			var p = project(595+(shot.from+(shot.to-shot.from)*t)*.91,475+(shot.fromY+(shot.toY-shot.fromY)*t)*.9,24+sin(t*PI)*(110 if shot.siege else 28))
			if shot.siege:
				draw_rect(Rect2(p-Vector2(5,4),Vector2(10,8)),Color('#a6b1a2'))
				draw_rect(Rect2(p+Vector2(2,0),Vector2(4,5)),Color('#53655b'))
			else:
				var dir = 1 if shot.side=='ally' else -1
				draw_line(p,p+Vector2(15,5)*dir,Color('#df984a') if shot.fire else Color('#eee1b5'),2)
	for p in particles: draw_rect(Rect2(p.pos,Vector2(p.size,p.size)),p.color)
	for c in captions: draw_string(world_font,c.pos,text(c.text),HORIZONTAL_ALIGNMENT_LEFT,-1,18,c.color)
	draw_set_transform(Vector2.ZERO)
