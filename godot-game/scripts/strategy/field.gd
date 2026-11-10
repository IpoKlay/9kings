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
	var names={'tree':'树林','fruit':'果树 · 食物+木材','berries':'浆果','deer':'鹿','sheep':'羊','boar':'野猪','cattle':'牛','fish':'鱼','iron':'铁矿脉','farm':'农田'}
	for resource in r.resources:
		if resource.remaining<=0:continue
		var p: Vector2=resource.pos
		if resource.kind in ['tree','fruit']:
			draw_texture_rect(tex('environments/oak'),Rect2(p-Vector2(48,90),Vector2(96,105)),false)
			if resource.kind=='fruit':
				for offset in [Vector2(-12,-45),Vector2(14,-60),Vector2(26,-32)]:draw_rect(Rect2(p+offset,Vector2(6,6)),Color('#b84c37'))
		elif resource.kind=='iron':
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
		label(p+Vector2(-65,35),names[resource.kind]+' '+str(int(resource.remaining)))
	var art={'town':'medic_3','barracks':'legion_1','range':'archer_1','stable':'cavalry_1','factory':'siege_2','academy':'training_2','house':'medic_1','outpost':'guard_1','fortress':'guard_3','wall':'guard_2','gate':'guard_2','wall_tower':'guard_3'}
	for b in r.buildings:
		if b.hp<=0 or b.kind=='farm':continue
		var p: Vector2=b.pos
		if b.kind=='barracks':draw_arc(p,360,0,TAU,64,Color('#c6be6666'),2)
		var size: float=r.strategy.buildings[b.kind].size
		draw_texture_rect(tex('building_'+art[b.kind]),Rect2(p-Vector2(size*.65,size),Vector2(size*1.3,size*1.3)),false,Color(1,1,1,.5 if b.remaining>0 or b.open else 1.))
		label(p+Vector2(-75,40),('敌方 ' if b.side=='enemy' else '')+r.strategy.buildings[b.kind].name+(' 建造%.0f秒'%b.remaining if b.remaining>0 else ' 已打开' if b.open else ''))
		draw_rect(Rect2(p-Vector2(30,size+10),Vector2(60,5)),Color('#493c35'))
		draw_rect(Rect2(p-Vector2(30,size+10),Vector2(60*b.hp/b.max_hp,5)),Color('#91b07a'))
		if not b.queue.is_empty():label(p+Vector2(-75,62),'生产 %.0f秒'%b.queue[0].remaining)
	for shot in r.rain:
		draw_arc(shot.point,80,0,TAU,24,Color('#e6cf8a'),2)
		for i in 6:
			var p: Vector2=shot.point+Vector2((i%3-1)*20,(i/3)*20)-Vector2(0,shot.remaining*70)
			draw_line(p-Vector2(3,16),p,Color('#fff0c5'),2)
