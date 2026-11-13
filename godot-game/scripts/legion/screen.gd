extends Control
signal closed
const Battle = preload('res://scripts/legion/battle.gd')
const Field = preload('res://scripts/legion/field.gd')
const Formation = preload('res://scripts/legion/formations.gd')
var app
var rules = Battle.new()
var field
var selected: Array = [0]
var camera = Vector2(1300,850)
var zoom = 0.74
var paused = false
var accumulator = 0.0
var aiming = false
var aim_rain = false
var left_drag = false
var right_drag = false
var panning = false
var drag_screen = Vector2.ZERO
var drag_world = Vector2.ZERO
var mouse_world = Vector2.ZERO
var card_buttons = []
var card_bars = []
var form_buttons = {}
var status: Label
var message: Label
var detail: Label
var clock: Label
var start_button: Button
var pause_button: Button
var rain_button: Button
var result_panel: PanelContainer
var result_text: Label
var label_box: StyleBoxFlat
var hud: Control
var selection_signature = ''

func style(background: String, border: String = '#74684c') -> StyleBoxFlat:
	var s = StyleBoxFlat.new(); s.bg_color = Color(background); s.border_color = Color(border)
	s.set_border_width_all(2); s.set_content_margin_all(12)
	return s

func label(text: String, position: Vector2, dimensions: Vector2, size: int = 24) -> Label:
	var l = Label.new(); l.text = text; l.position = position; l.size = dimensions
	l.add_theme_color_override('font_color',Color('#ece3c8')); l.add_theme_font_size_override('font_size',size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; hud.add_child(l)
	return l

func button(text: String, position: Vector2, dimensions: Vector2, callback: Callable) -> Button:
	var b = Button.new(); b.text = text; b.position = position; b.size = dimensions
	b.focus_mode = Control.FOCUS_NONE; b.add_theme_font_size_override('font_size',22)
	b.add_theme_stylebox_override('normal',style('#28352f'))
	b.add_theme_stylebox_override('hover',style('#415044','#d8c18b'))
	b.add_theme_stylebox_override('pressed',style('#53624b','#f4d794'))
	b.add_theme_stylebox_override('disabled',style('#242a26','#474b3c'))
	b.pressed.connect(callback); hud.add_child(b)
	return b

func panel(position: Vector2, dimensions: Vector2):
	var p = Panel.new(); p.position = position; p.size = dimensions
	p.add_theme_stylebox_override('panel',style('#18231feb','#968365')); hud.add_child(p)
	return p

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = preload('res://assets/fonts/game_pixel_theme.tres')
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label_box = style('#15231ce8','#75876d')
	var ground = ColorRect.new(); ground.color = Color('#1e2a22'); ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); ground.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(ground)
	field = Field.new(); field.screen = self; field.font = get_theme_default_font(); add_child(field)
	hud = Control.new(); hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(hud)
	hud.draw.connect(draw_selection)
	panel(Vector2.ZERO,Vector2(1920,89))
	label('鹰旗之下   /   林缘会战',Vector2(28,12),Vector2(600,40),29)
	label('军团指挥 · 战前部署',Vector2(30,53),Vector2(460,28),19)
	status = label('',Vector2(620,17),Vector2(650,52),26)
	clock = label('',Vector2(1210,24),Vector2(170,42),24)
	pause_button = button('暂停',Vector2(1390,19),Vector2(110,50),toggle_pause)
	button('总览',Vector2(1514,19),Vector2(110,50),func(): camera = Vector2(1300,850); zoom = 0.74)
	button('重置布阵',Vector2(1638,19),Vector2(140,50),retry)
	button('菜单',Vector2(1792,19),Vector2(100,50),closed.emit)
	panel(Vector2(0,871),Vector2(1920,209))
	label('我方军团',Vector2(28,881),Vector2(250,32),23)
	label('1–4 选队  /  Shift 多选',Vector2(240,885),Vector2(520,30),18)
	for i in 4:
		var card = button('',Vector2(26+i*221,920),Vector2(210,123),func(): select_regiment(i,Input.is_key_pressed(KEY_SHIFT)))
		card.add_theme_font_size_override('font_size',22); card_buttons.append(card)
		var bar = ColorRect.new(); bar.position = Vector2(13,100); bar.size = Vector2(184,7)
		bar.color = Color('#131e19'); bar.mouse_filter = Control.MOUSE_FILTER_IGNORE; card.add_child(bar)
		var fill = ColorRect.new(); fill.size = Vector2(184,7); fill.color = Color('#80bda9')
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE; bar.add_child(fill); card_bars.append(fill)
	detail = label('',Vector2(940,884),Vector2(940,36),23)
	var column = 0
	for form in Formation.NAMES:
		var key: String = form
		var b = button(Formation.NAMES[form],Vector2(938+column*146,928),Vector2(137,44),func(): rules.set_formation(selected,key))
		form_buttons[form] = b; column += 1
	button('H  坚守',Vector2(938,985),Vector2(145,47),func(): rules.command(selected,'hold'))
	button('A  接敌',Vector2(1094,985),Vector2(145,47),func(): rules.command(selected,'auto'))
	button('R  撤退休整',Vector2(1250,985),Vector2(174,47),func(): rules.command(selected,'retreat'))
	rain_button = button('V  箭雨',Vector2(1435,985),Vector2(160,47),arm_rain)
	start_button = button('开  战',Vector2(1610,985),Vector2(278,47),start_battle)
	start_button.add_theme_stylebox_override('normal',style('#7d5032','#ebcc87'))
	message = label('',Vector2(28,822),Vector2(1860,42),22)
	message.add_theme_color_override('font_outline_color',Color('#17251b')); message.add_theme_constant_override('outline_size',5)
	label('左键选军团 / 拖框多选   ·   右键移动或集火   ·   右拖布阵朝向   ·   中键/方向键移图   ·   滚轮缩放   ·   空格暂停',Vector2(28,1048),Vector2(1860,26),18)
	result_panel = PanelContainer.new(); result_panel.position = Vector2(625,320); result_panel.size = Vector2(670,330)
	result_panel.add_theme_stylebox_override('panel',style('#19251cf5','#d8bf80')); hud.add_child(result_panel)
	var box = VBoxContainer.new(); box.add_theme_constant_override('separation',24); result_panel.add_child(box)
	result_text = Label.new(); result_text.add_theme_font_size_override('font_size',29); result_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(result_text)
	var retry_button = Button.new(); retry_button.text = '重新布阵'; retry_button.custom_minimum_size.y = 54; retry_button.pressed.connect(retry); box.add_child(retry_button)
	result_panel.hide()
	update_ui()

func start_battle():
	if rules.start() and app != null: app.sound.play_rally()

func retry():
	rules = Battle.new(); paused = false; accumulator = 0; selected = [0]; aim_rain = false
	left_drag = false; right_drag = false; result_panel.hide(); camera = Vector2(1300,850); zoom = 0.74
	update_ui()

func toggle_pause():
	if rules.phase == 'battle': paused = not paused

func arm_rain():
	if rules.phase == 'battle' and selected.any(func(id): return rules.regiments[id].kind == 'archer'):
		aim_rain = true; rules.report = '左键指定箭雨落点，右键取消。'

func select_regiment(id: int, additive: bool = false):
	if rules.members(rules.regiments[id]).is_empty(): return
	if not additive: selected = [id]
	elif id in selected: selected.erase(id)
	else: selected.append(id)
	aim_rain = false

func screen_to_world(p: Vector2) -> Vector2:
	var local = (p-Vector2(960,469))/zoom + Field.project(camera)
	return Vector2(local.x,local.y/0.67)

func world_to_screen(p: Vector2) -> Vector2: return Vector2(960,469)+(Field.project(p)-Field.project(camera))*zoom

func hit_regiment(p: Vector2, side: String) -> int:
	var best = -1; var distance = 55.0
	for s in rules.soldiers:
		if s.hp <= 0 or rules.regiments[s.regiment].side != side: continue
		var screen_p = world_to_screen(s.pos)-Vector2(0,18*zoom)
		var d = p.distance_to(screen_p)
		if d < distance: distance = d; best = s.regiment
	for id in field.label_rects:
		var rect: Rect2 = field.label_rects[id]
		rect.position = field.position+rect.position*zoom; rect.size *= zoom
		if rules.regiments[id].side == side and rect.has_point(p): return id
	return best

func _process(dt: float):
	if not paused and rules.phase == 'battle':
		accumulator += minf(dt,0.15)
		while accumulator >= 1.0/30.0:
			rules.update(1.0/30.0); accumulator -= 1.0/30.0
	var pan = Vector2(float(Input.is_key_pressed(KEY_RIGHT))-float(Input.is_key_pressed(KEY_LEFT)),float(Input.is_key_pressed(KEY_DOWN))-float(Input.is_key_pressed(KEY_UP)))
	camera += pan*dt*700/zoom
	camera = camera.clamp(Vector2(500,400),Vector2(2100,1350))
	field.position = Vector2(960,469)-Field.project(camera)*zoom; field.scale = Vector2.ONE*zoom
	field.queue_redraw(); update_ui(); hud.queue_redraw()

func update_ui():
	if status == null: return
	status.text = '我方  %d    :    %d  敌方' % [rules.strength('ally'),rules.strength('enemy')]
	clock.text = '%02d:%02d   %s' % [int(rules.elapsed)/60,int(rules.elapsed)%60,'布阵' if rules.phase == 'deploy' else '胜利' if rules.phase == 'victory' else '失败' if rules.phase == 'defeat' else '暂停' if paused else '交战']
	message.text = rules.report
	pause_button.text = '继续' if paused else '暂停'; pause_button.disabled = rules.phase != 'battle'
	start_button.disabled = rules.phase != 'deploy'; start_button.text = '开  战' if rules.phase == 'deploy' else '战斗进行中' if rules.phase == 'battle' else '战斗结束'
	for i in 4:
		var r: Dictionary = rules.regiments[i]; var count = rules.members(r).size()
		var order: String = {'auto':'自动接敌','hold':'坚守','move':'行军','retreat':'撤退休整','attack':'集火'}.get(r.order,'')
		var state = '阵亡' if count == 0 else '换阵 %.1fs'%r.form_time if r.form_time > 0 else Formation.NAMES[r.form] if rules.phase == 'deploy' else order
		card_buttons[i].text = '%d  %s\n%d/35 · %s' % [i+1,rules.stats[r.kind].name,count,state]
		if not card_buttons[i].has_meta('selected') or card_buttons[i].get_meta('selected') != (i in selected):
			card_buttons[i].set_meta('selected',i in selected)
			card_buttons[i].add_theme_stylebox_override('normal',style('#3b4e3b' if i in selected else '#26332c','#e0c58c' if i in selected else '#69684e'))
		card_bars[i].size.x = 184.0*rules.hp(r)/(r.initial*rules.stats[r.kind].hp)
	var living = selected.filter(func(id): return not rules.members(rules.regiments[id]).is_empty())
	for form in form_buttons:
		form_buttons[form].disabled = living.is_empty() or not living.all(func(id): return form in Formation.OPTIONS[rules.regiments[id].kind]) or rules.phase not in ['deploy','battle']
		form_buttons[form].tooltip_text = formation_help(form)
	if living.size() == 1:
		var r: Dictionary = rules.regiments[living[0]]; var d: Dictionary = rules.stats[r.kind]
		detail.text = '%s · 生命 %d/%d  攻击 %d  护甲 %d/%d%s' % [d.name,rules.hp(r),rules.members(r).size()*d.hp,d.attack,d.melee_armor,d.ranged_armor,'  换阵冷却 %.0fs'%maxf(0,r.form_cd-r.form_time) if r.form_cd > 0 else '']
	else: detail.text = '已选 %d 个军团 · 只显示共同支持的阵型' % living.size()
	var archers = living.filter(func(id): return rules.regiments[id].kind == 'archer')
	rain_button.disabled = rules.phase != 'battle' or archers.is_empty()
	rain_button.text = 'V 箭雨 %.0fs'%rules.regiments[archers[0]].rain_cd if not archers.is_empty() and rules.regiments[archers[0]].rain_cd > 0 else 'V  箭雨'
	if rules.phase in ['victory','defeat']:
		result_panel.show()
		result_text.text = '%s\n\n我方存活 %d / 140　阵亡 %d\n敌方阵亡 %d / 120\n\n幸存士兵已恢复生命' % ['战斗胜利' if rules.phase == 'victory' else '战斗失败',rules.strength('ally'),rules.losses.ally,rules.losses.enemy]

func formation_help(form: String) -> String:
	return {'default':'七人横列、五排纵深；前排优先排满。','wedge':'冲锋伤害提高；冲锋命中降低敌军攻击、移动与攻击速度。','ring':'护甲和攻击提高，移动大幅降低；中央留空，可部署另一军团。','scatter':'间距加大，移动加快；范围伤害减半。','testudo':'护甲大幅提高，移动大幅降低；敌方骑兵冲锋可暂时破阵。','dense':'普通攻击降低，箭雨伤害提高。'}.get(form,'')

func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_4: select_regiment(event.keycode-KEY_1,event.shift_pressed)
		match event.keycode:
			KEY_SPACE: toggle_pause()
			KEY_ENTER: start_battle()
			KEY_ESCAPE: aim_rain = false; selected.clear(); left_drag = false; right_drag = false
			KEY_H: rules.command(selected,'hold')
			KEY_A: rules.command(selected,'auto')
			KEY_R: rules.command(selected,'retreat')
			KEY_V: arm_rain()
			KEY_F: camera = Vector2(1300,850); zoom = 0.74
	if event is InputEventMouseMotion:
		mouse_world = screen_to_world(event.position)
		if panning: camera -= Vector2(event.relative.x,event.relative.y/0.67)/zoom
		if left_drag or right_drag: queue_redraw()
	# Releases outside the playfield must end the drag too.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_MIDDLE: panning = false
		if event.position.y < 90 or event.position.y > 815:
			left_drag = false; right_drag = false

func _unhandled_input(event: InputEvent):
	if rules.phase in ['victory','defeat']: return
	if not event is InputEventMouseButton: return
	var point: Vector2 = event.position
	if point.y < 90 or point.y > 815: return
	mouse_world = screen_to_world(point)
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: zoom = minf(1.4,zoom*1.1)
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: zoom = maxf(0.55,zoom/1.1)
	if event.button_index == MOUSE_BUTTON_MIDDLE: panning = event.pressed
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if aim_rain: rules.arrow_rain(selected,mouse_world); aim_rain = false; return
			left_drag = true; drag_screen = point
		elif left_drag:
			left_drag = false
			if drag_screen.distance_to(point) > 12:
				if not event.shift_pressed: selected.clear()
				var rectangle = Rect2(drag_screen,point-drag_screen).abs()
				for r in rules.regiments:
					if r.side == 'ally' and r.id not in selected and rules.members(r).any(func(id): return rectangle.has_point(world_to_screen(rules.soldiers[id].pos))): selected.append(r.id)
			else:
				var id = hit_regiment(point,'ally')
				if id >= 0: select_regiment(id,event.shift_pressed)
				elif not event.shift_pressed: selected.clear()
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if aim_rain: aim_rain = false; return
			right_drag = true; drag_world = mouse_world; drag_screen = point
		elif right_drag:
			right_drag = false
			if selected.is_empty(): return
			if rules.phase == 'deploy': rules.deploy(selected,drag_world,drag_world.direction_to(mouse_world) if point.distance_to(drag_screen) > 18 else Vector2.ZERO)
			else:
				var id = hit_regiment(point,'enemy')
				if id >= 0: rules.command(selected,'attack',Vector2.ZERO,id)
				else: rules.command(selected,'move',mouse_world)

func draw_selection():
	if left_drag:
		var rect = Rect2(drag_screen,get_local_mouse_position()-drag_screen).abs()
		hud.draw_rect(rect,Color('#a6d4b522')); hud.draw_rect(rect,Color('#d2e4bb'),false,2)
