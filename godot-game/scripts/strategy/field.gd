extends Node2D
const StaticArt=preload('res://scripts/strategy/static_art.gd')
const Fortifications=preload('res://scripts/strategy/fortification_art.gd')
var static_art=StaticArt.new()
var fortifications=Fortifications.new()
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
		draw_texture_rect(static_art.texture('M01'),hill,false)
		label(hill.position+Vector2(25,35),'丘陵')
	for y in range(int(r.river.position.y),int(r.river.end.y),100):
		var height=minf(100.,r.river.end.y-y)
		draw_texture_rect_region(static_art.texture('M02'),Rect2(r.river.position.x,y,r.river.size.x,height),Rect2(0,0,32,32*height/100.))
	for cliff in r.cliffs:
		for x in range(int(cliff.position.x),int(cliff.end.x),64):
			for y in range(int(cliff.position.y),int(cliff.end.y),64):
				var dimensions=Vector2(minf(64.,cliff.end.x-x),minf(64.,cliff.end.y-y))
				draw_texture_rect_region(static_art.texture('M03'),Rect2(Vector2(x,y),dimensions),Rect2(Vector2.ZERO,dimensions))
		label(cliff.position+Vector2(10,30),'悬崖 · 不可通行')
	var names={'tree':'树林','fruit':'果树 · 食物+木材','berries':'浆果','deer':'鹿','sheep':'羊','boar':'野猪','cattle':'牛','fish':'鱼','iron':'铁矿脉','farm':'农田','large_iron':'大型铁矿脉','wolf':'狼（可采集）'}
	for resource in r.resources:
		if resource.remaining<=0 or not r.world.discovered(resource.pos):continue
		var p: Vector2=resource.pos
		if resource.kind in ['tree','fruit']:
			draw_texture_rect(tex('environments/oak'),Rect2(p-Vector2(48,90),Vector2(96,105)),false)
			if resource.kind=='fruit':
				for offset in [Vector2(-12,-45),Vector2(14,-60),Vector2(26,-32)]:draw_rect(Rect2(p+offset,Vector2(6,6)),Color('#b84c37'))
		elif StaticArt.RESOURCES.has(resource.kind):
			var id: String=StaticArt.RESOURCES[resource.kind]
			var width: float={'iron':64.,'large_iron':96.,'farm':72.,'cattle':44.,'deer':40.,'boar':40.,'sheep':32.,'fish':28.}.get(resource.kind,32.)
			draw_texture_rect(static_art.texture(id),static_art.sprite_rect(id,p,width),false)
		else:
			# Unsupplied bushes and fauna retain their existing fallback.
			var tint=Color('#ddc69b') if resource.kind!='fish' else Color('#bbd5d3')
			draw_rect(Rect2(p-Vector2(13,13),Vector2(26,17)),tint)
			draw_rect(Rect2(p+Vector2(8,-20),Vector2(12,12)),tint)
			if resource.kind!='fish':
				for dx in [-9,7]:draw_rect(Rect2(p+Vector2(dx,4),Vector2(4,12)),tint)
		label(p+Vector2(-65,35),names[resource.kind]+('' if resource.kind in ['tree','farm'] else ' '+str(int(resource.remaining))))
	for b in fortifications.structures_with_joints(r):
		if b.kind=='corner':fortifications.draw(self,b);continue
		if b.hp<=0 or b.kind=='farm' and b.remaining<=0:continue
		var p: Vector2=b.pos
		if b.kind in ['wall','gate']:
			fortifications.draw(self,b)
			if b.kind=='gate':label(p+Vector2(-30,38),'城门·开' if b.open else '城门·关')
			if b.remaining>0:construction_meter(b,p+Vector2(-30,24))
			continue
		if b.kind=='farm':
			draw_texture_rect(static_art.texture('B23'),static_art.sprite_rect('B23',p,72.),false,Color(1,1,1,.5))
			construction_meter(b,p+Vector2(-30,34));continue
		if b.kind=='barracks':draw_arc(p,360,0,TAU,64,Color('#c6be6666'),2)
		var size: float=r.strategy.buildings[b.kind].size
		var id=static_art.building_id(b.kind,r.town_level if b.side=='ally' else 1)
		draw_texture_rect(static_art.texture(id),static_art.sprite_rect(id,p,size*1.6),false,Color(1,1,1,.5 if b.remaining>0 else 1.))
		label(p+Vector2(-75,40),('敌方 ' if b.side=='enemy' else '')+r.strategy.buildings[b.kind].name+(' · 建造中' if b.remaining>0 else ''))
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

func construction_meter(b: Dictionary,at: Vector2):
	var progress=clampf(1.-b.remaining/trial.rules.strategy.buildings[b.kind].seconds,0.,1.)
	draw_rect(Rect2(at,Vector2(60,6)),Color('#493c35'))
	draw_rect(Rect2(at,Vector2(60*progress,6)),Color('#d5ac60'))
