extends Control
## A native Control scene; textures, paths, buttons and windows all run in Godot.
var app
var selected = ''
var history_open = false
var points = JSON.parse_string(FileAccess.get_file_as_string('res://data/expedition_positions.json'))
var content: Control
var info: Control
var notice_label: Label
var status_label: Label
var city_buttons: Dictionary = {}
var travel_button: Button
var textures = {}
var origin = Vector2(0,104)

func _ready():
	z_index = 30
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	render()

func tex(id: String) -> Texture2D:
	if not textures.has(id): textures[id] = load('res://assets/expedition/'+id+'.png')
	return textures[id]

func box(id: String = 'panel') -> StyleBoxTexture:
	var s = StyleBoxTexture.new()
	s.texture = tex(id)
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: s.set_texture_margin(side,5)
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return s

func panel(parent: Node,pos: Vector2,sz: Vector2) -> Panel:
	var p = Panel.new()
	p.position = pos
	p.size = sz
	p.add_theme_stylebox_override('panel',box())
	parent.add_child(p)
	return p

func text(parent: Node,value: String,pos: Vector2,sz: Vector2,font_size: int = 24,color: Color = Color('#f0dfb0')) -> Label:
	return app.label(parent,value,pos,sz,font_size,color)

func btn(parent: Node,value: String,pos: Vector2,sz: Vector2,callback: Callable,gold: bool = false) -> Button:
	var b = Button.new()
	b.text = value
	b.position = pos
	b.size = sz
	b.add_theme_stylebox_override('normal',box('gold' if gold else 'button'))
	b.add_theme_stylebox_override('hover',box('gold'))
	b.add_theme_stylebox_override('pressed',box('panel'))
	b.add_theme_stylebox_override('disabled',box('panel'))
	b.add_theme_stylebox_override('focus',box('gold'))
	b.add_theme_font_size_override('font_size',24)
	b.add_theme_color_override('font_color',Color('#f1dfb0'))
	b.pressed.connect(func():
		app.sound.play('click')
		callback.call())
	parent.add_child(b)
	return b

func point(id: String) -> Vector2:
	return Vector2(points[id][0],points[id][1])+origin

func render():
	if app == null: return
	if is_instance_valid(content):
		remove_child(content)
		content.queue_free()
	content = Control.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	var backing = ColorRect.new()
	backing.color=Color('#193a50')
	backing.size=Vector2(1920,1080)
	backing.mouse_filter=Control.MOUSE_FILTER_IGNORE
	content.add_child(backing)
	city_buttons.clear()
	travel_button = null
	var background = TextureRect.new()
	background.texture = tex('mediterranean')
	background.position = origin
	background.size = Vector2(1920,840)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(background)
	var exp = app.expedition
	var state = exp.state
	var distances = exp.distances()
	for edge in exp.data.edges:
		var past = false
		for i in range(1,state.visited.size()):
			if state.visited[i-1]==edge[0] and state.visited[i]==edge[1]: past=true
		var available = edge[0] == state.current and exp.can_travel(edge[1])
		var color = Color('#d9ae61') if past else Color('#ffe5a8') if available else Color('#a2bcbf55')
		var path = Line2D.new()
		path.points = PackedVector2Array([point(edge[0]),point(edge[1])])
		path.width = 3 if past or available else 1
		path.default_color = color
		path.antialiased = false
		content.add_child(path)
		if available:
			var arrow = text(content,'◆',point(edge[0]).lerp(point(edge[1]),.55)-Vector2(12,12),Vector2(30,30),23,color)
			arrow.rotation = 0
	for n in exp.data.nodes:
		var p = point(n.id)
		var current = n.id == state.current
		var visited = n.id in state.visited
		var available = exp.can_travel(n.id)
		var b = Button.new()
		b.name = 'City_'+n.id
		b.position = p-Vector2(84,90)
		b.size = Vector2(168,126)
		b.tooltip_text = exp.node_text(n.id)+' · '+(app.tx('军团驻地','Legion camp') if current else app.tx('可前往','Reachable') if available else app.tx('已通过','Visited') if visited else app.tx('查看情报','View intel'))
		for name in ['normal','hover','pressed','focus']: b.add_theme_stylebox_override(name,StyleBoxEmpty.new())
		var art = TextureRect.new()
		art.texture = tex(n.kind+'_'+('current' if current else 'visited' if visited else 'idle'))
		art.position = Vector2(20,0)
		art.size = Vector2(128,100)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(art)
		var title_width = clampf(app.font.get_string_size(exp.node_text(n.id),HORIZONTAL_ALIGNMENT_LEFT,-1,22).x+22,70,208)
		var title = text(b,exp.node_text(n.id),Vector2((168-title_width)*.5,91),Vector2(title_width,30),22,Color('#ffe3a0') if available or current else Color('#eee3b8'))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_stylebox_override('normal',box('gold' if current else 'panel'))
		var badge = text(b,app.tx('⚑ 军团','⚑ Legion') if current else app.tx('◆ 可前往','◆ Reachable') if available else '✓' if visited else '' if exp.known(n.id) else '?',Vector2(0,121),Vector2(168,25),18)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if not visited and not distances.has(n.id): b.modulate.a = .45
		b.pressed.connect(func():select_city(n.id))
		b.mouse_entered.connect(func():art.modulate=Color(1.2,1.15,1.02))
		b.mouse_exited.connect(func():art.modulate=Color.WHITE)
		content.add_child(b)
		city_buttons[n.id]=b
	var header = panel(content,Vector2(12,12),Vector2(1896,88))
	text(header,'SPQR',Vector2(24,20),Vector2(90,45),26,Color('#e4bc76'))
	text(header,app.tx('鹰旗之下 · 地中海远征','Under the Eagle · Mediterranean Campaign'),Vector2(140,12),Vector2(650,40),28)
	text(header,app.tx('公元前30年 · 历史地理 / 架空战役','30 BC · Historical geography / Fictional campaign'),Vector2(142,51),Vector2(630,27),18,Color('#abbfbe'))
	status_label = text(header,app.tx('军团驻地  ','Legion at  ')+exp.node_text(state.current)+app.tx('     生命 %d/3','     Lives %d/3')%app.campaign.g.defense,Vector2(810,26),Vector2(660,45),26)
	if state.finished:
		btn(header,app.tx('开始新远征','New campaign'),Vector2(1530,16),Vector2(230,58),app.restart_expedition,true)
	elif app.has_battle_report():
		btn(header,app.tr_text('View report'),Vector2(1530,16),Vector2(230,58),func():
			app.show_camp()
			app.open_dialog('result'),true)
	else:
		btn(header,app.tx('返回战场','Back to battle') if app.campaign.g.phase=='battle' else app.tx('军营 / 构筑','Back to camp'),Vector2(1530,16),Vector2(230,58),app.show_camp)
	btn(header,'⚙',Vector2(1780,16),Vector2(80,58),func():app.open_dialog('settings'))
	var footer = panel(content,Vector2(12,950),Vector2(1896,118))
	notice_label = text(footer,exp.notice_text(),Vector2(22,10),Vector2(1500,34),23)
	var complete = 0
	for id in exp.data.goals:
		if id in state.visited: complete+=1
	text(footer,app.tx('%d / 4 战区目标','%d / 4 objectives')%complete,Vector2(1640,14),Vector2(235,30),21,Color('#b7c9c7'))
	for i in 4:
		var done = exp.data.goals[i] in state.visited
		text(footer,('◆ ' if done else '◇ ')+[app.tx('西地中海','Western Mediterranean'),app.tx('北非','North Africa'),app.tx('东地中海','Eastern Mediterranean'),app.tx('内海终章','The Inland Sea')][i],Vector2(155+i*450,53),Vector2(350,30),22,Color('#c4d5a8') if done else Color('#ffe3a2') if i==complete else Color('#8ca4b0'))
	text(footer,app.tx('前方两站情报可见 · 选择分支后不折返 · 本局军团与建筑保留','Intel covers the next two stops · Routes are one-way · Your army and buildings carry over'),Vector2(22,88),Vector2(1500,25),17,Color('#99b2bf'))
	if selected != '': render_info()

func select_city(id: String):
	selected = id
	history_open = false
	app.sound.play('click')
	render()

func close_info():
	selected = ''
	history_open = false
	render()

func render_info():
	var exp = app.expedition
	var n = exp.nodes[selected]
	var known = exp.known(selected)
	var visited = selected in exp.state.visited
	var distance = exp.distances().get(selected,-1)
	var can = exp.can_travel(selected)
	var h = 628 if history_open else 462
	info = panel(content,Vector2(1468,930-h),Vector2(430,h))
	info.name = 'CityInfo'
	var kind = app.tx('军团驻地','Legion camp') if selected==exp.state.current else app.tx('已通过','Visited') if visited else app.tx('支线已关闭','Route closed') if distance<0 else {'home':app.tx('集结地','Assembly point'),'port':app.tx('友军港口','Friendly port'),'event':app.tx('城邦事件','City event'),'battle':app.tx('普通战斗','Battle'),'elite':app.tx('精英战斗','Elite battle'),'boss':app.tx('战区决战','Regional showdown'),'final':app.tx('最终决战','Final battle')}[n.kind] if known else app.tx('情报未明','Unknown')
	text(info,kind,Vector2(22,17),Vector2(330,25),19,Color('#b6c9c2'))
	text(info,exp.node_text(n.id),Vector2(22,51),Vector2(350,45),34)
	text(info,n.latin,Vector2(23,98),Vector2(360,26),20,Color('#9fb7c2'))
	btn(info,'×',Vector2(372,14),Vector2(43,43),close_info)
	text(info,app.tx('敌军','Enemy forces'),Vector2(22,139),Vector2(350,29),21,Color('#dbbf7d'))
	var wave = exp.encounter(selected) if known else {}
	var enemy_text = app.tx('等待斥候报告','Awaiting scout reports') if not known else app.tx('无敌军 · 和平访问','No enemies · Peaceful visit')
	if not wave.is_empty():
		var counts = {}
		for type in wave.roster: counts[type]=counts.get(type,0)+1
		var parts: Array[String] = []
		for type in counts: parts.append({'enemy':app.tx('步兵','Infantry'),'archer':app.tx('弓兵','Archers'),'guard':app.tx('重盾兵','Shield guards'),'cavalry':app.tx('骑兵','Cavalry'),'siege':app.tx('投石车','Catapults')}[type]+' ×'+str(counts[type]))
		enemy_text = ' · '.join(parts)
	text(info,enemy_text,Vector2(22,175),Vector2(387,64),20)
	text(info,(app.tx('生命 ×%.2f · 攻击 ×%.2f','Health ×%.2f · Attack ×%.2f')%[wave.health,wave.attack]) if not wave.is_empty() else exp.node_text(selected,'title') if known else app.tx('前方两站以内揭示敌军与奖励','Enemies and rewards are revealed within two stops.'),Vector2(22,238),Vector2(385,40),18,Color('#9fb7c2'))
	text(info,app.tx('奖励','Rewards'),Vector2(22,276),Vector2(360,28),21,Color('#dbbf7d'))
	text(info,exp.reward_text(selected) if known else app.tx('尚未侦察','Not yet scouted'),Vector2(22,309),Vector2(385,65),22)
	btn(info,('▾' if history_open else '▸')+app.tx(' 历史档案',' History'),Vector2(20,378),Vector2(185,33),func():
		history_open=not history_open
		render()).add_theme_font_size_override('font_size',18)
	if history_open: text(info,exp.node_text(selected,'history'),Vector2(22,420),Vector2(385,145),20,Color('#bfd0c9'))
	# Keep the action visible at the bottom of the compact information window.
	travel_button=btn(info,(app.tx('进入战斗  ⚔','Battle  ⚔') if n.roster!=null else app.tx('进入城邦  →','Visit  →')) if can else app.tx('已通过 · 选择下一站','Already visited') if visited else app.tx('本局无法折返','Route closed') if distance<0 else app.tx('尚未到达','Not reachable'),Vector2(220,378 if not history_open else 564),Vector2(190,62),func():app.travel_to(selected),true)
	travel_button.name='Travel'
	travel_button.disabled=not can
	travel_button.add_theme_font_size_override('font_size',21)
