extends Node2D
const Art = preload('res://scripts/tactical/approved_unit_art.gd')
const Formation = preload('res://scripts/legion/formations.gd')
const GROUND = preload('res://assets/environments/iberia-rts.png')
const BLUE = Color('#80d5cf')
const RED = Color('#e58c75')
var screen
var art = Art.new()
var font: Font
var label_rects = {}

static func project(p: Vector2) -> Vector2: return Vector2(p.x,p.y*0.67)

func text_at(p: Vector2, value: String, color: Color, size: int = 22):
	draw_string(font,p,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func _draw():
	if screen == null: return
	var r = screen.rules
	var candidates = screen.combination_candidates()
	draw_texture_rect(GROUND,Rect2(0,0,2600,1700*0.67),false)
	if r.phase == 'deploy':
		var zone: Rect2 = r.DEPLOYMENT
		draw_rect(Rect2(project(zone.position),project(zone.size)),Color('#4bacbd20'))
		draw_rect(Rect2(project(zone.position),project(zone.size)),Color('#9ed8c68c'),false,2)
		text_at(project(zone.position)+Vector2(18,32),'我方部署区',Color('#c9edcd'),25)
	for group in r.regiments:
		if r.members(group).is_empty(): continue
		var selected: bool = group.id in screen.selected
		var tint = BLUE if group.side == 'ally' else RED
		if group.charge_queued or group.charge_state != '':
			var from = project(group.pos); var to = project(group.charge_point)
			draw_line(from,to,Color('#efb775'),3)
			draw_arc(to,20,0,TAU,24,Color('#efb775'),3)
			text_at(to+Vector2(23,5),'冲锋终点',Color('#ffe1a0'),20)
		if selected or group.id in candidates:
			for id in r.members(group):
				var p = project(r.soldiers[id].pos)
				draw_arc(p,14 if group.id in candidates else 12,0,TAU,16,Color('#ffe099') if group.id in candidates else Color(tint,0.8),2.2)
			var origin = project(group.pos)
			var tip = project(group.pos+group.heading*125)
			draw_line(origin,tip,Color('#f6dda3'),3)
			var back = (origin-tip).normalized()
			draw_line(tip,tip+back.rotated(0.5)*16,Color('#f6dda3'),3)
			draw_line(tip,tip+back.rotated(-0.5)*16,Color('#f6dda3'),3)
			if not group.path.is_empty():
				var line = PackedVector2Array([project(group.pos)])
				for p in group.path: line.append(project(p))
				draw_polyline(line,Color('#f3dc9c99'),2)
				draw_arc(project(group.goal),20,0,TAU,24,Color('#f6dda3'),2)
	var ordered = r.soldiers.duplicate()
	ordered.sort_custom(func(a,b): return a.pos.y < b.pos.y)
	for s in ordered:
		if s.hp <= 0 and r.elapsed-s.death_time > 16: continue
		var group: Dictionary = r.regiments[s.regiment]
		var action = 'idle'
		if s.hp <= 0: action = 'death'
		elif s.charging: action = 'charge'
		elif s.attack_age < 0.65: action = 'attack'
		elif s.moving: action = 'walk'
		var id: String = r.stats[group.kind].art
		var bearing = Art.bearing_for(s.heading)
		var clip = Art.clip(id,action,bearing)
		var ms: float = fmod(s.walk*700.0,clip.duration_ms) if s.moving else fmod((r.elapsed+s.id*0.071)*1000.0,clip.duration_ms)
		if action == 'attack': ms = minf(clip.duration_ms-1,s.attack_age/0.65*clip.duration_ms)
		if action == 'death': ms = minf(clip.duration_ms-1,(r.elapsed-s.death_time)*1000.0)
		var frame = clip.frame_at(ms)
		var p = project(s.pos)
		var scale_factor = 1.25
		if s.hp > 0:
			draw_set_transform(p,0,Vector2(1,0.4))
			draw_circle(Vector2.ZERO,13,Color('#17251b70'))
			draw_set_transform(Vector2.ZERO)
		var color = Color.WHITE
		if s.hp <= 0: color = Color(0.7,0.65,0.57,clampf((16-(r.elapsed-s.death_time))/4.0,0,0.8))
		elif r.elapsed-s.hit_time < 0.12: color = Color(1.7,1.35,1.15)
		draw_texture_rect_region(art.page(id,action,group.side),Rect2((p-clip.anchors[frame]*scale_factor).round(),clip.regions[frame].size*scale_factor),clip.regions[frame],color)
		if s.hp > 0 and s.hp < s.max_hp and group.id in screen.selected:
			draw_rect(Rect2(p-Vector2(11,68),Vector2(22,3)),Color('#26302c'))
			draw_rect(Rect2(p-Vector2(11,68),Vector2(22*s.hp/s.max_hp,3)),BLUE)
		if s.hp > 0 and s.wedge_debuff > 0:
			draw_arc(p,15,0,TAU,12,Color('#e8bf73'),2)
			draw_line(p+Vector2(-5,-7),p+Vector2(5,7),Color('#e8bf73'),2)
	label_rects.clear()
	for group in r.regiments:
		var count = r.members(group).size()
		if count == 0: continue
		var p = project(group.pos)+Vector2(-76,50)
		var label_height = 78 if group.pair >= 0 else 52
		for attempt in 8:
			var candidate = Rect2(p-Vector2(8,24),Vector2(173,label_height))
			if not label_rects.values().any(func(rect): return rect.grow(4).intersects(candidate)): break
			p.y += label_height+6
		label_rects[group.id] = Rect2(p-Vector2(8,24),Vector2(173,label_height))
		var tint = BLUE if group.side == 'ally' else RED
		if p.y-project(group.pos).y > 60: draw_line(project(group.pos),p+Vector2(70,-24),Color(tint,0.45),1)
		draw_style_box(screen.label_box,label_rects[group.id])
		text_at(p,'%s%s %d' % [str(group.id+1)+' ' if group.side == 'ally' else '',r.stats[group.kind].name,count],tint,21)
		var bar_y = 36 if group.pair >= 0 else 10
		draw_rect(Rect2(p+Vector2(0,bar_y),Vector2(150,5)),Color('#25372c'))
		draw_rect(Rect2(p+Vector2(0,bar_y),Vector2(150*r.hp(group)/(group.initial*r.stats[group.kind].hp),5)),tint)
		if group.pair >= 0: text_at(p+Vector2(0,24),Formation.NAMES[group.form],BLUE,18)
		if group.form_time > 0:
			text_at(p+Vector2(0,-34),'换阵 %.1f 秒'%group.form_time,Color('#ffe4a3'),21)
		elif group.broken > 0: text_at(p+Vector2(0,-34),'破阵 %.1f秒'%group.broken,RED,21)
		elif group.id in candidates: text_at(p+Vector2(0,-34),'可组合',Color('#ffe099'),21)
		elif group.form == 'free': text_at(p+Vector2(0,-34),'自由攻击',Color('#ffe099'),21)
		elif group.charge_state != '': text_at(p+Vector2(0,-34),'整队中' if group.charge_state == 'forming' else '冲锋中',Color('#ffe099'),21)
	for shot in r.projectiles:
		var t: float = clampf(shot.age/shot.duration,0,1)
		var point: Vector2 = project(shot.from.lerp(shot.to,t))-Vector2(0,sin(t*PI)*110)
		var direction: Vector2 = (project(shot.to)-project(shot.from)).normalized()
		if shot.rain:
			draw_arc(project(shot.to),74,0,TAU,32,Color('#eac88088'),2)
			for i in 17:
				var p = point+Vector2(sin(i*7.3)*65,cos(i*3.7)*38)
				draw_line(p-direction*16,p,Color('#f3dfb5'),2)
		else: draw_line(point-direction*14,point,Color('#f3dfb5'),2)
	for e in r.effects:
		var p = project(e.pos); var fade: float = 1-e.age/0.5
		if e.kind == 'charge': draw_arc(p,12+e.age*50,0,TAU,12,Color(1,0.9,0.65,fade),3)
		elif e.kind == 'rain': draw_arc(p,74,0,TAU,28,Color(0.8,0.7,0.5,fade),2)
		else:
			draw_line(p+Vector2(-4,-24),p+Vector2(4,-36),Color(1,0.9,0.65,fade),2)
	if screen.right_drag:
		var p = project(screen.drag_world)
		draw_arc(p,24,0,TAU,20,Color('#ffe1a0'),2)
		draw_line(p,project(screen.mouse_world),Color('#ffe1a0'),3)
	if screen.aim_rain:
		draw_arc(project(screen.mouse_world),92,0,TAU,36,Color('#ffe1a0'),3)
	if screen.aim_order != '':
		var p = project(screen.mouse_world)
		var color = Color('#efa56e') if screen.aim_order in ['attack_move','charge'] else BLUE
		draw_arc(p,24,0,TAU,20,color,3)
		draw_line(p-Vector2(32,0),p+Vector2(32,0),color,2)
		draw_line(p-Vector2(0,22),p+Vector2(0,22),color,2)
