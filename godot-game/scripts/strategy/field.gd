extends Node2D
var trial
var landscape_rect=Rect2(-300,-300,3800,3800)
var textures={}
func tex(path: String) -> Texture2D:
	if not textures.has(path):textures[path]=load('res://assets/'+path+'.png')
	return textures[path]
func advance(_dt: float):queue_redraw()
func label(point: Vector2,text: String,color: Color=Color('#f7edcd')):
	draw_string(trial.hint.get_theme_font('font'),point,text,HORIZONTAL_ALIGNMENT_LEFT,-1,19,color)
func _draw():
	if trial==null:return
	var r=trial.rules
	draw_rect(landscape_rect,Color('#4e583b'))
	for x in 4:
		for y in 4:draw_texture_rect_region(tex('environments/iberia-rts'),Rect2(x*800,y*800,800,800),Rect2(420,400,800,800))
	for hill in r.hills:
		draw_rect(hill,Color('#9e9c5966'))
		for i in 4:draw_rect(hill.grow(-i*24),Color('#b9b37888'),false,3)
		label(hill.position+Vector2(25,35),'丘陵')
	draw_rect(r.river,Color('#496e83'))
	for y in range(310,2600,32):draw_line(Vector2(2710,y),Vector2(2778,y),Color('#8cafa8'),3)
	for cliff in r.cliffs:
		draw_rect(cliff,Color('#575449'));draw_rect(cliff.grow(-12),Color('#8d8873'))
		label(cliff.position+Vector2(10,30),'悬崖 · 不可通行')
	var names={'tree':'树林','fruit':'果树 · 食物+木材','berries':'浆果','deer':'鹿','sheep':'羊','boar':'野猪','cattle':'牛','fish':'鱼','iron':'铁矿脉','farm':'农田','large_iron':'大型铁矿脉','wolf':'狼（可采集）'}
	for resource in r.resources:
		if resource.remaining<=0 or not r.world.discovered(resource.pos):continue
		var p: Vector2=resource.pos
		if resource.kind in ['tree','fruit']:
			draw_texture_rect(tex('environments/oak'),Rect2(p-Vector2(48,90),Vector2(96,105)),false)
			if resource.kind=='fruit':
				for offset in [Vector2(-12,-45),Vector2(14,-60),Vector2(26,-32)]:draw_rect(Rect2(p+offset,Vector2(6,6)),Color('#b84c37'))
		elif resource.kind in ['iron','large_iron']:
			draw_colored_polygon(PackedVector2Array([p+Vector2(-25,0),p+Vector2(-14,-30),p+Vector2(18,-37),p+Vector2(30,0)]),Color('#858d91'))
		elif resource.kind=='farm':
			draw_rect(Rect2(p-Vector2(30,25),Vector2(60,50)),Color('#756044'))
			for i in 5:draw_line(p+Vector2(-24+i*12,-20),p+Vector2(-24+i*12,20),Color('#b6af69'),4)
		else:
			# Pixel resource tokens identify harvestable fauna until dedicated sprites are authored.
			var tint=Color('#ddc69b') if resource.kind!='fish' else Color('#bbd5d3')
			draw_rect(Rect2(p-Vector2(13,13),Vector2(26,17)),tint)
			draw_rect(Rect2(p+Vector2(8,-20),Vector2(12,12)),tint)
			if resource.kind!='fish':
				for dx in [-9,7]:draw_rect(Rect2(p+Vector2(dx,4),Vector2(4,12)),tint)
		label(p+Vector2(-65,35),names[resource.kind]+('' if resource.kind in ['tree','farm'] else ' '+str(int(resource.remaining))))
	var art={'town':'medic_3','barracks':'legion_1','range':'archer_1','stable':'cavalry_1','factory':'siege_2','academy':'training_2','house':'medic_1','outpost':'guard_1','fortress':'guard_3','wall':'guard_2','gate':'guard_2','wall_tower':'guard_3'}
	for b in r.world.displayed_buildings(r):
		if b.hp<=0 or b.kind=='farm' and b.remaining<=0:continue
		var p: Vector2=b.pos
		if b.kind in ['wall','gate']:
			draw_wall(b)
			if b.remaining>0:construction_meter(b,p+Vector2(-30,24))
			continue
		if b.kind=='farm':
			draw_rect(Rect2(p-Vector2(30,25),Vector2(60,50)),Color('#75604480'))
			for i in 5:draw_line(p+Vector2(-24+i*12,-20),p+Vector2(-24+i*12,20),Color('#b6af6980'),4)
			construction_meter(b,p+Vector2(-30,34));continue
		if b.kind=='barracks':draw_arc(p,360,0,TAU,64,Color('#c6be6666'),2)
		var size: float=r.strategy.buildings[b.kind].size
		draw_texture_rect(tex('building_'+art[b.kind]),Rect2(p-Vector2(size*.65,size),Vector2(size*1.3,size*1.3)),false,Color(1,1,1,.5 if b.remaining>0 or b.open else 1.))
		label(p+Vector2(-75,40),('敌方 ' if b.side=='enemy' else '')+r.strategy.buildings[b.kind].name+(' · 建造中' if b.remaining>0 else ' 已打开' if b.open else ''))
		draw_rect(Rect2(p-Vector2(30,size+10),Vector2(60,5)),Color('#493c35'))
		draw_rect(Rect2(p-Vector2(30,size+10),Vector2(60*b.hp/b.max_hp,5)),Color('#91b07a'))
		if b.remaining>0:construction_meter(b,p-Vector2(30,size+22))
		if not b.queue.is_empty():label(p+Vector2(-75,62),'生产 %.0f秒'%b.queue[0].remaining)
	for camp in r.world.camps:
		if not r.world.discovered(camp.pos):continue
		var p: Vector2=camp.pos
		draw_texture_rect(tex('building_training_2'),Rect2(p-Vector2(40,75),Vector2(80,80)),false,Color('#bf9785'))
		label(p+Vector2(-80,-90),'已清剿' if camp.claimed else '蛮族营寨' if camp.strong else '蛮族营地')
	for wolf in r.units:
		if wolf.get('wild',false) and wolf.hp>0 and r.unit_visible(wolf):
			var p: Vector2=wolf.pos
			draw_rect(Rect2(p-Vector2(18,16),Vector2(32,16)),Color('#8d8b83'))
			draw_colored_polygon(PackedVector2Array([p+Vector2(12,-20),p+Vector2(28,-10),p+Vector2(12,-4)]),Color('#aaa79d'))
			for dx in [-12,8]:draw_line(p+Vector2(dx,-3),p+Vector2(dx+sin(r.elapsed*12)*4,8),Color('#555751'),4)
	for shot in r.rain:
		draw_arc(shot.point,80,0,TAU,24,Color('#e6cf8a'),2)
		for i in 6:
			var p: Vector2=shot.point+Vector2((i%3-1)*20,(i/3)*20)-Vector2(0,shot.remaining*70)
			draw_line(p-Vector2(3,16),p,Color('#fff0c5'),2)

func draw_wall(b: Dictionary):
	var p: Vector2=b.pos
	var dimensions=Vector2(b.get('wall_length',64.),34.)
	if b.kind=='gate' and b.open:
		label(p+Vector2(-30,-20),'城门·开');return
	var opacity=.5 if b.remaining>0 else 1.
	draw_set_transform(p,b.get('wall_angle',0.))
	var rect=Rect2(-dimensions*.5,dimensions)
	draw_rect(rect,Color(Color('#6b6b62'),opacity));draw_rect(Rect2(rect.position-Vector2(0,9),dimensions),Color(Color('#aaa78c'),opacity))
	for i in int(ceil(dimensions.x/16.)):
		var at=rect.position+Vector2(i*16,0)
		draw_rect(Rect2(at-Vector2(0,12),Vector2(10,10)),Color(Color('#d0c6a1'),opacity))
	draw_set_transform(Vector2.ZERO)
	if b.kind=='gate':label(p+Vector2(-30,-22),'城门·关')

func construction_meter(b: Dictionary,at: Vector2):
	var progress=clampf(1.-b.remaining/trial.rules.strategy.buildings[b.kind].seconds,0.,1.)
	draw_rect(Rect2(at,Vector2(60,6)),Color('#493c35'))
	draw_rect(Rect2(at,Vector2(60*progress,6)),Color('#d5ac60'))
